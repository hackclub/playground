module Admin
  class ShipsController < BaseController
    before_action :set_ship, except: :index
    before_action :refuse_own_ship, only: %i[review fraud snapshot send_back]

    LIST_CAP = 300

    # Every ship and the stage it is in, newest first, with a tab per stage.
    def index
      @stage = params[:stage].presence_in(Ship::STAGES.keys)
      @counts = Ship.group(:state, :review_status, :fraud_status).count.each_with_object(Hash.new(0)) do |((state, review, fraud), n), by|
        key = state != "pending" ? state : (review == "pending" ? "awaiting_review" : (fraud == "pending" ? "awaiting_fraud" : nil))
        by[key] += n if key
      end
      scope = @stage ? Ship.in_stage(@stage) : Ship.all
      @total = scope.count
      @ships = scope.includes(:user, :reviewer, :fraud_reviewer, project: :ships).order(created_at: :desc).limit(LIST_CAP)
    end

    def show
      @snapshot = ShipSnapshot.new(@ship)
      load_page
    end

    # The name, description, and links reviewers see. The screenshots save
    # through Admin::ShipScreenshotsController. A field that fails its check
    # comes back on the page with what was typed.
    def snapshot
      @snapshot = ShipSnapshot.new(@ship)
      case @snapshot.update(params.fetch(:snapshot, {}).permit(*ShipSnapshot::TEXT), by: current_user)
      when true then redirect_to admin_ship_path(@ship, stage: params[:stage], flow: params[:flow]), notice: "snapshot saved"
      when nil then redirect_to admin_ship_path(@ship, stage: params[:stage], flow: params[:flow]), notice: "nothing changed"
      else
        load_page
        render :show, status: :unprocessable_entity
      end
    end

    def review
      return stale unless @ship.review_status == "pending" && @ship.pending?
      return taken("review") if Claim.held_by_other?(@ship, "review", current_user)
      return stardance_shipped if params[:verdict] == "approve" && StardanceRepos.for_project(@ship.project, @ship.snapshot["code_url"]) == :shipped
      seconds = (params[:approved_hours].to_f * 3600).round
      case params[:verdict]
      when "approve" then @ship.approve_review!(by: current_user, seconds:, judgement: params[:judgement], feedback: params[:feedback], deflation_reason: params[:deflation_reason],
                                                art_seconds: (params[:approved_art_hours].present? ? (params[:approved_art_hours].to_f * 3600).round : nil))
      when "changes" then @ship.return_for_changes!(by: current_user, judgement: params[:judgement], feedback: params[:feedback])
      when "reject" then @ship.reject_review!(by: current_user, judgement: params[:judgement], feedback: params[:feedback])
      when "ban" then @ship.ban_for_fraud!(by: current_user, notes: params[:notes], judgement: params[:judgement])
      else return head(:bad_request)
      end
      @ship.claims.where(stage: "review").delete_all
      done("review", "review saved")
    rescue ArgumentError => e
      redirect_to admin_ship_path(@ship, stage: "review", flow: params[:flow]), alert: e.message
    end

    def fraud
      return stale unless @ship.fraud_status == "pending" && @ship.pending?
      return taken("fraud") if Claim.held_by_other?(@ship, "fraud", current_user)
      case params[:verdict]
      when "pass" then @ship.pass_fraud!(by: current_user, notes: params[:notes])
      when "deduct" then @ship.pass_fraud!(by: current_user, deduction_seconds: (params[:deduct_hours].to_f * 3600).round, notes: params[:notes])
      when "ban" then @ship.ban_for_fraud!(by: current_user, notes: params[:notes])
      else return head(:bad_request)
      end
      @ship.claims.where(stage: "fraud").delete_all
      done("fraud", "fraud verdict saved")
    rescue ArgumentError => e
      redirect_to admin_ship_path(@ship, stage: "fraud", flow: params[:flow]), alert: e.message
    end

    # Pulls a ship that passed review, and waits for the fraud check, back to
    # the review queue.
    def send_back
      return stale unless @ship.sent_back_possible?
      return taken("fraud") if Claim.held_by_other?(@ship, "fraud", current_user)
      @ship.send_back_to_review!(by: current_user, reason: params[:reason])
      @ship.claims.where(stage: "fraud").delete_all
      redirect_to admin_ship_path(@ship, stage: "review"), notice: "sent back to review"
    rescue ArgumentError => e
      redirect_to admin_ship_path(@ship, stage: "fraud", flow: params[:flow]), alert: e.message
    end

    # The checklist saves on every tick.
    def checklist
      @ship.update!(review_checklist: @ship.review_checklist.merge(params.require(:key) => params[:value] == "1"))
      head :no_content
    end

    private

    def set_ship = @ship = Ship.find(params[:id])

    def load_page
      @stage = params[:stage].presence_in(%w[review fraud]) || (@ship.review_status == "pending" ? "review" : "fraud")
      @claim, @held = claim_for(@stage)
      @user = @ship.user
      @project = @ship.project
      repo_name = @project.github_repo
      @repo = repo_name && (Github.repo(repo_name) rescue nil)
      @readme = repo_name && Github.readme_html(repo_name) if @stage == "review"
      @commits = repo_name ? Github.recent_commits(repo_name) : []
      @live = (Hackatime.for(@user).stats(@project.hackatime_projects) rescue nil) if @user.hackatime_connected?
      @other_ships = @user.ships.where.not(id: @ship.id).includes(:project).order(created_at: :desc)
      @duplicates = Project.where(code_url: @project.code_url).where.not(user_id: @user.id).includes(:user) if @project.code_url.present?
      @shared_hackatime = User.where(hackatime_user_id: @user.hackatime_user_id).where.not(id: @user.id) if @user.hackatime_user_id.present?
      @unified = UnifiedSearch.check(@ship.snapshot["code_url"])
      @stardance = StardanceRepos.for_project(@project, @ship.snapshot["code_url"])
      @stardance_ids = @stardance == :shipped ? StardanceRepos.project_ids(@ship.snapshot["code_url"]) : []
      load_ai_coding if @stage == "review" && @ship.review_status == "pending" && @ship.pending?
      @send_backs = AuditEvent.where(subject: @ship, action: "review.send_back").includes(:actor).order(:created_at)
      @justification = Justification.new(@ship).to_s if @ship.review_seconds
    end

    # A ship from before the cap has no AI figure. Ask Hackatime with the
    # participant's token and keep the answer. If it won't say, no cap applies.
    def load_ai_coding
      return unless @ship.snapshot["ai_coding_seconds"].nil? && @ship.snapshot["window"] && @user.hackatime_connected?
      window = @ship.snapshot["window"]
      ai = Shipper.ai_coding(@project, @user, Time.zone.parse(window["starts_at"]), Time.zone.parse(window["ends_at"]), before: @ship.created_at)
      @ship.update_columns(snapshot: @ship.snapshot.merge("ai_coding_seconds" => ai)) unless ai.nil?
    end

    # The queues skip an admin's own ships, and a direct post can't judge or edit one.
    def refuse_own_ship
      redirect_to admin_ship_path(@ship), alert: "someone else judges your own ship" if @ship.user_id == current_user.id
    end

    def claim_for(stage)
      return [ nil, false ] unless @ship.pending?
      claim, took = Claim.acquire(@ship, stage, current_user, force: params[:take].present?)
      [ claim, !took ]
    end

    def done(stage, message)
      path = flow? ? admin_person_path(@ship.user) : public_send(:"admin_#{stage}_path")
      redirect_to path, notice: message
    end

    # Stardance reviews it, so the approve is refused. Changes and reject stay open.
    def stardance_shipped = redirect_to(admin_ship_path(@ship, stage: "review", flow: params[:flow]), alert: StardanceRepos.message(StardanceRepos.project_ids(@ship.snapshot["code_url"])))
    def stale = redirect_to(admin_ship_path(@ship), alert: "this ship already moved on")
    def taken(stage) = redirect_to(admin_ship_path(@ship, stage:), alert: "someone else holds this ship")
  end
end
