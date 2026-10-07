# Where readers stop in one guide (GuideSections) over some days: each
# section in guide order, with how many browsers reached it, their share of
# the first section's, and how many fewer reached it than the section
# before. The biggest drop is marked. A later section can count more than an
# earlier one, as a link to a part of the guide skips what is above it.
class GuideFunnel
  Row = Data.define(:section, :name, :readers, :share, :drop, :drop_share, :biggest)

  attr_reader :guide, :days, :rows

  def initialize(guide, days)
    @guide = guide
    @days = days
    counts = GuideSectionDay.readers(guide.key, days)
    first = counts.fetch(guide.sections.first, 0)
    before = nil
    @rows = guide.sections.map do |section|
      readers = counts.fetch(section, 0)
      drop = before && before - readers
      row = Row.new(section:, name: GuideSections::NAMES.fetch(section), readers:, share: (readers.fdiv(first) if first.positive?),
                    drop:, drop_share: (drop.fdiv(before) if drop && before.positive?), biggest: false)
      before = readers
      row
    end
    biggest = @rows.select { it.drop.to_i.positive? }.max_by(&:drop)
    @rows = @rows.map { it.equal?(biggest) ? it.with(biggest: true) : it } if biggest
  end

  def empty? = rows.sum(&:readers).zero?
end
