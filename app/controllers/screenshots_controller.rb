# The server half of the screenshot uploads. A pet holds up to
# ScreenshotLimits::PER_PET screenshots in order, and the first is its cover.
# An upload goes: owner check, request size before the body is read, rate
# limit, then ScreenshotProcessor, and only then storage. Removing or
# replacing a screenshot deletes its file, unless a ship was reviewed with it.
class ScreenshotsController < ApplicationController
  before_action :require_login
  before_action :set_project
  before_action :refuse_oversized_request, only: :create
  rate_limit to: ScreenshotLimits::PER_HOUR, within: 1.hour, by: -> { current_user.id }, only: :create,
             with: -> { render json: { error: "too many uploads; try again in an hour" }, status: :too_many_requests }

  FULL = "a pet holds up to #{ScreenshotLimits::PER_PET} screenshots. remove one to add another.".freeze
  GONE = "that screenshot is gone. reload the page.".freeze

  # Adds a screenshot at the end, or with replace=id takes that one's place.
  def create
    replacing = params[:replace].presence
    return render_error(GONE, :not_found) if replacing && !@project.screenshot(replacing)
    return render_error(FULL, :unprocessable_entity) if !replacing && full?
    file = params.require(:screenshot)
    return render_error("send one image file", :unprocessable_entity) unless file.respond_to?(:read)

    result = ScreenshotProcessor.call(file.read(ScreenshotLimits::MAX_REQUEST_BYTES + 1))
    # Development and production share credentials, so anything but
    # production writes under its environment's name in the bucket.
    prefix = Rails.env.production? ? "" : "#{Rails.env}/"
    id = SecureRandom.uuid
    key = "#{prefix}screenshots/#{@project.id}/#{id}.webp"
    shot = { "id" => id, "key" => key, "url" => ScreenshotStore.current.put(key, result.bytes) }

    # Another upload may have landed while this one was processed.
    replaced = nil
    saved = @project.with_lock do
      list = @project.screenshots.dup
      if replacing
        index = list.index { it["id"] == replacing }
        next false unless index
        replaced = list[index]
        list[index] = shot
      else
        next false if full?
        list << shot
      end
      @project.update!(screenshots: list)
    end
    unless saved
      ScreenshotStore.current.delete(key)
      return render_error(replacing ? GONE : FULL, replacing ? :not_found : :unprocessable_entity)
    end
    forget(replaced) if replaced
    AuditEvent.record(current_user, @project, "screenshot.upload", key:, width: result.width, height: result.height)

    render json: { id:, url: shot["url"], width: result.width, height: result.height }, status: :created
  rescue ActionController::ParameterMissing
    render_error("choose an image first", :unprocessable_entity)
  rescue ScreenshotProcessor::Rejected => e
    render_error(e.message, :unprocessable_entity)
  rescue ScreenshotStore::NotConfigured => e
    render_error(e.message, :service_unavailable)
  end

  def destroy
    shot = nil
    @project.with_lock do
      shot = @project.screenshot(params[:id])
      @project.update!(screenshots: @project.screenshots - [ shot ]) if shot
    end
    return render_error(GONE, :not_found) unless shot
    forget(shot)
    AuditEvent.record(current_user, @project, "screenshot.remove", key: shot["key"])
    head :no_content
  end

  # The screenshots in a new order, by id. The ids must be the pet's own.
  def order
    ids = Array(params[:ids]).map(&:to_s)
    moved = @project.with_lock do
      next false unless ids.uniq.size == ids.size && ids.sort == @project.screenshots.map { it["id"] }.sort
      @project.update!(screenshots: ids.map { @project.screenshot(it) })
    end
    moved ? head(:no_content) : render_error("the screenshots changed. reload the page.", :conflict)
  end

  private

  def set_project = @project = current_user.projects.find(params[:project_id])

  def full? = @project.screenshots.size >= ScreenshotLimits::PER_PET

  def render_error(message, status) = render(json: { error: message }, status:)

  def refuse_oversized_request
    return unless request.content_length.to_i > ScreenshotLimits::MAX_REQUEST_BYTES
    render_error("the upload is over #{ScreenshotLimits::MAX_REQUEST_BYTES / 1024 / 1024} MB", :content_too_large)
  end

  # A ship keeps the screenshots it was reviewed with, so their files stay.
  def forget(shot)
    return unless shot["key"]
    urls = [ shot["url"], ScreenshotStore.current.url(shot["key"]) ]
    kept = @project.ships.any? { (Array(it.snapshot["screenshots"]) + [ it.snapshot["screenshot_url"] ]).intersect?(urls) }
    ScreenshotStore.current.delete(shot["key"]) unless kept
  end
end
