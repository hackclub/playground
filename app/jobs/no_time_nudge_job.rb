# Every hour, marks the participants due the "no time yet" email
# (NoTimeNudge).
class NoTimeNudgeJob < ApplicationJob
  queue_as :default

  def perform = NoTimeNudge.run
end
