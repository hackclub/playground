# Helpers for the new site, without the desktop (NewSite): its top bar, my
# pets, the ship list inside the guide, and the guide in steps. They ask
# nothing about the flag. The routes, the controllers, and the layout do.
module NewSiteHelper
  # The guide in steps shows the same screenshots as the one long guide,
  # except that the Plugins tab is cropped to the tabs and the plugin row.
  STEP_SHOTS = GuideHelper::SHOTS.except("plugins-tab").merge("plugins-tab-enabled" => [ 1416, 240 ]).freeze

  # The new site's own Stimulus controllers, in app/javascript/new_site. They
  # are not in the import map, so a page of the desktop site neither lists nor
  # loads them. The new site's layout registers them.
  CONTROLLERS = Rails.root.glob("app/javascript/new_site/*_controller.js").map { it.basename(".js").to_s.delete_suffix("_controller") }.sort.freeze

  def new_site_controllers_tag
    lines = [ %(import { application } from "controllers/application") ]
    CONTROLLERS.each_with_index do |name, i|
      lines << "import c#{i} from #{json_escape(asset_path("new_site/#{name}_controller.js").to_json)}"
      lines << "application.register(#{json_escape(name.dasherize.to_json)}, c#{i})"
    end
    tag.script(lines.join("\n").html_safe, type: "module")
  end

  # The top bar's open tab: the guide, or the participant's pets, which
  # holds each pet's own pages too. Other pages, such as the requirements,
  # open no tab.
  def topbar_tab
    case controller_path
    when "guides" then :guide
    when "projects" then :pets
    end
  end

  # One of the top bar's tabs. The open one says so to a screen reader: it is
  # the page itself, or, on one of its pages, the part of the site.
  def topbar_tab_link(label, path, open)
    current = (current_page?(path) ? "page" : "true") if open
    link_to label, path, class: "topbar-tab", aria: { current: }
  end

  # Hours on the meter beside the guide, short and to the minute: "12m",
  # "2h", "2h 1m". Minutes round down, so the meter never shows a goal's
  # hours before they are all there.
  def meter_hours(seconds)
    h, m = (seconds.to_i / 60).divmod(60)
    return "#{m}m" if h.zero?
    m.zero? ? "#{h}h" : "#{h}h #{m}m"
  end

  # The total on the meter's tag. Past the top of the bar it shows whole
  # hours, as "14h", so the tag always fits its lane.
  def meter_total(hours)
    seconds = hours.total_seconds.to_i
    seconds >= hours.scale_seconds ? "#{seconds / 3600}h" : meter_hours(seconds)
  end

  # A pet's card on my pets, which shows all there is about the pet.
  def pet_card_path(project) = projects_path(anchor: "pet-#{project.id}")

  # The ship list inside the guide's Ship it step, rather than on its own
  # page. Its saves, checks, and ship say so with from=guide, so the list
  # comes back without the requirements line, and a redirect goes back to the
  # guide's Ship it step.
  def ship_in_guide? = controller_path.in?(%w[guides guide_steps]) || params[:from] == "guide"
  def ship_from = ship_in_guide? ? { from: "guide" } : {}

  # The new site's ship list asks for the pet's itch.io page, where its guide
  # uploads the pet.
  PLAYABLE_TIP = "where people get your pet: its itch.io page, with your pet uploaded there. " \
                 "the page needs to load for anyone.".freeze
  def ship_tip(item) = item.tip == ShipChecklist::TIPS[:playable] ? PLAYABLE_TIP : item.tip

  # A small line under a step that differs by computer: which computer the
  # guide shows it for, and a button for each other one. Hidden until
  # os_note_controller.js runs, since without it every version shows, labelled.
  def guide_os_note
    names = GuideHelper::SYSTEMS.slice("macos", "windows", "linux")
    tag.p(class: "os-note", hidden: true, data: { os_note_target: "note" }) do
      safe_join([
        "for ", safe_join(names.map { |os, name| tag.span(name, data: { os: }) }), ". on another computer? ",
        safe_join(names.map { |os, name| tag.button(name, type: "button", value: os, class: "linkish", data: { action: "os-note#pick" }) }, " ")
      ])
    end
  end

  # A screen recording in the guide in steps, as guide_video makes it, with
  # no button: a click on the recording pauses it or plays it. It takes the
  # focus, so Enter or Space does the same, and it says whether it is paused.
  def guide_step_video(slug, label)
    width, height, av1 = GuideHelper::VIDEOS.fetch(slug)
    sources = []
    sources << tag.source(src: video_path("guide/#{slug}.webm"), type: 'video/webm; codecs="av01.0.08M.08"') if av1
    sources << tag.source(src: video_path("guide/#{slug}.mp4"), type: "video/mp4")
    tag.figure(class: "guide-video", data: { controller: "video-click" }) do
      tag.video(safe_join(sources), muted: true, loop: true, playsinline: true, preload: "none",
                                    poster: image_path("guide/#{slug}-poster.webp"), width: width / 2, height: height / 2,
                                    "aria-label": "#{label} Press to pause or play.", tabindex: 0, role: "button",
                                    data: { video_click_target: "video",
                                            action: "click->video-click#toggle keydown.enter->video-click#toggle keydown.space->video-click#toggle" })
    end
  end

  # A screenshot in the guide in steps, at half its file's size.
  def guide_step_shot(name, alt)
    width, height = STEP_SHOTS.fetch(name)
    image_tag("guide/#{name}.webp", alt:, width: width / 2, height: height / 2, loading: "lazy", decoding: "async", class: "guide-shot")
  end
end
