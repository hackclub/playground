module Admin
  class StatsController < BaseController
    def show
      @stats = ProgramStats.new
      @nps = NpsStats.new
      @guide_funnel = guide_funnel
      @journeys = GuideJourneyStats.new(guide: @guide_funnel.guide, days: @guide_funnel.days,
                                        touch: params[:progress_touch], source: params[:progress_source])
      @signups = SignupSourceStats.new(days: picked_days(:signup_from, :signup_to), touch: params[:signup_touch])
    end

    private

    # Where readers stop in the guide picked, the desktop's by default, over
    # the days picked, the program window's by default.
    def guide_funnel
      guide = GuideSections.find(params[:progress_guide]) || GuideSections.all.first
      GuideFunnel.new(guide, picked_days(:progress_from, :progress_to))
    end

    # The days from two date parameters, the program window's by default,
    # put the right way round.
    def picked_days(from_name, to_name)
      window = ProgramWindow.current
      from = date_param(from_name) || window.starts_at.in_time_zone(ProgramWindow::ZONE).to_date
      to = date_param(to_name) || (window.ends_at - 1).in_time_zone(ProgramWindow::ZONE).to_date
      from, to = to, from if from > to
      from..to
    end

    def date_param(name)
      Date.iso8601(params[name].to_s)
    rescue Date::Error
      nil
    end
  end
end
