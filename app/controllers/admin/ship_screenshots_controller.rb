# The screenshots in a ship's snapshot, edited by an admin with the same grid
# participants use, so it speaks the same JSON. An upload goes through the same
# checks and storage path as a participant's. Only the ship changes: the pet
# keeps its own screenshots. A file that leaves the ship is deleted only when
# neither the pet nor any of its ships still shows it.
module Admin
  class ShipScreenshotsController < BaseController
    before_action :set_ship
    before_action :refuse_own_ship
    before_action :refuse_oversized_request, only: :create

    FULL = "a ship holds up to #{ScreenshotLimits::PER_PET} screenshots. remove one to add another.".freeze
    GONE = "that screenshot is gone. reload the page.".freeze

    # Adds a screenshot at the end, or with replace=id takes that one's place.
    def create
      replacing = params[:replace].presence
      return render_error(GONE, :not_found) if replacing && !@snapshot.screenshot(replacing)
      return render_error(FULL, :unprocessable_entity) if !replacing && full?(@snapshot.screenshot_urls)
      file = params.require(:screenshot)
      return render_error("send one image file", :unprocessable_entity) unless file.respond_to?(:read)

      result = ScreenshotProcessor.call(file.read(ScreenshotLimits::MAX_REQUEST_BYTES + 1))
      key = ScreenshotStore.key_for(@ship.project, SecureRandom.uuid)
      url = ScreenshotStore.current.put(key, result.bytes)

      replaced = nil
      saved = @snapshot.update_screenshots(by: current_user, action: "snapshot.screenshot.upload", key:, replaced: replacing) do |urls|
        if replacing
          index = urls.index { ShipSnapshot.shot_id(it) == replacing } or next
          replaced = urls[index]
          urls[index] = url
        else
          next if full?(urls)
          urls << url
        end
        urls
      end
      unless saved
        ScreenshotStore.current.delete(key)
        return render_error(replacing ? GONE : FULL, replacing ? :not_found : :unprocessable_entity)
      end
      forget(replaced) if replaced

      render json: { id: ShipSnapshot.shot_id(url), url:, width: result.width, height: result.height }, status: :created
    rescue ActionController::ParameterMissing
      render_error("choose an image first", :unprocessable_entity)
    rescue ScreenshotProcessor::Rejected => e
      render_error(e.message, :unprocessable_entity)
    rescue ScreenshotStore::NotConfigured => e
      render_error(e.message, :service_unavailable)
    end

    def destroy
      removed = nil
      @snapshot.update_screenshots(by: current_user, action: "snapshot.screenshot.remove", id: params[:id]) do |urls|
        removed = urls.find { ShipSnapshot.shot_id(it) == params[:id] } or next
        urls - [ removed ]
      end
      return render_error(GONE, :not_found) unless removed
      forget(removed)
      head :no_content
    end

    # The screenshots in a new order, by id. The ids must be the ship's own.
    def order
      ids = Array(params[:ids]).map(&:to_s)
      moved = @snapshot.update_screenshots(by: current_user, action: "snapshot.screenshot.order") do |urls|
        by_id = urls.index_by { ShipSnapshot.shot_id(it) }
        next unless ids.uniq.size == ids.size && ids.sort == by_id.keys.sort
        ids.map { by_id[it] }
      end
      moved ? head(:no_content) : render_error("the screenshots changed. reload the page.", :conflict)
    end

    private

    def set_ship
      @ship = Ship.find(params[:ship_id])
      @snapshot = ShipSnapshot.new(@ship)
    end

    def refuse_own_ship
      render_error("someone else edits your own ship", :forbidden) if @ship.user_id == current_user.id
    end

    def full?(urls) = urls.size >= ScreenshotLimits::PER_PET

    def render_error(message, status) = render(json: { error: message }, status:)

    def refuse_oversized_request
      return unless request.content_length.to_i > ScreenshotLimits::MAX_REQUEST_BYTES
      render_error("the upload is over #{ScreenshotLimits::MAX_REQUEST_BYTES / 1024 / 1024} MB", :content_too_large)
    end

    # Deletes the file behind a URL that left the ship, unless the pet or one
    # of its ships still shows it, or it is not in our bucket.
    def forget(url)
      store = ScreenshotStore.current
      host = store.url("")
      return unless url.to_s.start_with?(host)
      project = @ship.project.reload
      in_use = project.screenshot_urls.include?(url) || project.ships.any? { ShipSnapshot.screenshot_urls(it).include?(url) }
      store.delete(url.delete_prefix(host)) unless in_use
    end
  end
end
