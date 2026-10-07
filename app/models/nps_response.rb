# One answer to the NPS form: how likely the participant is to recommend
# playground to a friend, from 0 to 10, and what they wrote. A participant
# with no answer from the last 12 hours is due: a ship needs an answer, and
# once they have some Hackatime time, nps.exe opens by itself on the
# desktop. There is no reward for one. NpsStats turns the answers into the
# admin's NPS.
class NpsResponse < ApplicationRecord
  belongs_to :user
  belongs_to :project, optional: true

  SCORES = 0..10
  # NPS's three groups by score. NPS is the share of promoters minus the
  # share of detractors.
  PROMOTERS = 9..10
  PASSIVES = 7..8
  DETRACTORS = 0..6
  # Where an answer came from: nps.exe on the desktop, or a ship.
  SOURCES = %w[daily ship].freeze
  # How often the site asks. An answer spares the participant for this
  # long, and a skipped nps.exe stays shut as long (see landing.js).
  INTERVAL = 12.hours

  # The questions after the score, in order, and whether each needs an
  # answer. The form, its submit button, and the validations all read this.
  QUESTIONS = {
    doing_well: { label: "what are we doing well?", required: true },
    improve: { label: "what's something we can improve?", required: true },
    anything_else: { label: "anything else you want to tell us?", required: false }
  }.freeze
  FIELDS = [ :score, *QUESTIONS.keys ].freeze
  MAX_LENGTH = 5000

  validates :score, numericality: { only_integer: true, in: SCORES }
  validates :source, inclusion: { in: SOURCES }
  validates :project, presence: true, if: -> { source == "ship" }
  validates(*QUESTIONS.select { |_, question| question[:required] }.keys, presence: true)
  validates(*QUESTIONS.keys, length: { maximum: MAX_LENGTH })

  # Tests of anything but the NPS turn the asking off (test_helper.rb), so
  # nps.exe neither opens nor has an icon, and a ship needs no answer.
  class << self
    attr_writer :asking
    def asking = @asking.nil? ? true : @asking
  end

  # Who answers: a signed-in participant. An admin at work and a banned
  # person are never asked.
  def self.participant?(user) = user.present? && !user.acts_as_admin? && !user.banned?
  def self.asks?(user) = asking && participant?(user)

  def self.answered_within?(user, interval = INTERVAL, now: Time.current) = where(user:, created_at: (now - interval)..).exists?

  # A participant the site asks, with no answer in the last 12 hours. A
  # ship needs an answer from them.
  def self.due?(user, now: Time.current) = asks?(user) && !answered_within?(user, now:)

  # nps.exe opens by itself only for a due participant with some Hackatime
  # time, summed over every day: as much as makes someone active on the
  # admin stats. A newcomer with none can still open it from its icon.
  def self.ask?(user, now: Time.current)
    due?(user, now:) && CodingHour.where(user:).sum(:seconds) >= ProgramStats::ACTIVE_CODING_SECONDS
  end

  # The Eastern day a time falls in, as the admin stats count days.
  def self.day(time = Time.current) = time.in_time_zone(ProgramWindow::ZONE).to_date
end
