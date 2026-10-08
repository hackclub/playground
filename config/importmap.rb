# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "landing"
pin "confetti"
# Where this browser came from, first on every page of the site (application,
# landing), and the guides' journey, only on the guides' pages.
pin "attribution"
pin "guide_journey", to: "guide/journey.js", preload: false
