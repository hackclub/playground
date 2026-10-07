module Admin
  class StatsController < BaseController
    def show
      @stats = ProgramStats.new
      @nps = NpsStats.new
      @guide_funnel = guide_funnel
    end

    private

    # Where readers stop in the guide picked, the desktop's by default, over
    # the days picked, the program window's by default.
    def guide_funnel
      guide = GuideSections.find(params[:progress_guide]) || GuideSections.all.first
      window = ProgramWindow.current
      from = date_param(:progress_from) || window.starts_at.in_time_zone(ProgramWindow::ZONE).to_date
      to = date_param(:progress_to) || (window.ends_at - 1).in_time_zone(ProgramWindow::ZONE).to_date
      from, to = to, from if from > to
      GuideFunnel.new(guide, from..to)
    end

    def date_param(name)
      Date.iso8601(params[name].to_s)
    rescue Date::Error
      nil
    end
  end
end
