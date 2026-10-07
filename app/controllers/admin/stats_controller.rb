module Admin
  class StatsController < BaseController
    def show
      @stats = ProgramStats.new
      @nps = NpsStats.new
    end
  end
end
