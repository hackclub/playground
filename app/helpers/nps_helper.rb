module NpsHelper
  # What the desktop needs for nps.exe: its icon shows for a participant the
  # site asks (data-nps), and it opens by itself when it should ask them now
  # (data-nps-ask). See NpsResponse.ask?.
  def nps_desktop_data
    return {} unless NpsResponse.asks?(current_user)
    { nps: "", nps_ask: ("" if NpsResponse.ask?(current_user)) }.compact
  end

  # Which of NPS's groups a score puts a person in.
  def nps_group(score)
    if NpsResponse::PROMOTERS.cover?(score) then "promoter"
    elsif NpsResponse::PASSIVES.cover?(score) then "passive"
    else "detractor"
    end
  end

  # An NPS as people write it: +40, 0, -25, or a dash for no answers.
  def nps_value(nps) = nps.nil? ? "—" : nps.zero? ? "0" : format("%+d", nps)
end
