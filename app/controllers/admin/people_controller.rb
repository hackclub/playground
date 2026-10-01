module Admin
  class PeopleController < BaseController
    def index
      @users = User.order(created_at: :desc).includes(:ships, :projects)
      if params[:q].present?
        q = "%#{User.sanitize_sql_like(params[:q])}%"
        @users = @users.where("email ILIKE :q OR display_name ILIKE :q OR first_name ILIKE :q OR last_name ILIKE :q OR slack_id ILIKE :q", q:)
      end
      # A count on the stats page opens this page on exactly the people it counts.
      if params[:filter].present?
        @filter = ProgramStats.new.group_for(params[:filter])
        @users = @filter ? @users.where(id: @filter.ids) : @users.none
        @count = @users.count
      end
      @users = @users.limit(100)
    end

    # One-shot mode: every stage for one participant, top to bottom.
    def show
      @user = User.find(params[:id])
      @ships = @user.ships.includes(:project, :reviewer, :fraud_reviewer).order(created_at: :desc)
      @redemptions = @user.redemptions.order(created_at: :desc)
      @hours = @user.hours
      @events = AuditEvent.where(subject: [ @user, *@ships, *@redemptions ]).includes(:actor).order(created_at: :desc).limit(30)
    end
  end
end
