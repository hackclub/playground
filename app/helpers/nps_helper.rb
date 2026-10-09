module NpsHelper
  # What the desktop needs for nps.exe: its icon shows for a participant the
  # site asks (data-nps), and it opens by itself when it should ask them now
  # (data-nps-ask). See NpsResponse.ask?.
  def nps_desktop_data
    return {} unless NpsResponse.asks?(current_user)
    { nps: "", nps_ask: ("" if NpsResponse.ask?(current_user)) }.compact
  end

  # On the new site the rock asks instead of nps.exe, for the same people at
  # the same times (NpsResponse.ask?). A page that asks already, such as the
  # form's own page or a ship list, sets :no_nps_rock and shows no rock.
  def nps_rock? = !content_for?(:no_nps_rock) && NpsResponse.ask?(current_user)

  # The rock, its bin, its popup, and the phones' 0 to 10 strip, once a page.
  # The guide places them at the end of its step, above the buttons to the
  # next one, and the layout at the end of any other page. The rock itself
  # sits in the corner of the screen wherever it is placed.
  def nps_rock
    return if @nps_rock_placed || !nps_rock?
    @nps_rock_placed = true
    render "nps_responses/rock"
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
