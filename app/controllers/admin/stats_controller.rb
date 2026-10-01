module Admin
  class StatsController < BaseController
    def show
      @stats = ProgramStats.new
    end
  end
end
