namespace :icons do
  desc "Bake the box around each desktop icon's drawn pixels into config/icon_bounds.yml"
  task bounds: :environment do
    IconBounds.bake
    puts "baked #{IconBounds::ICONS.size} icons into #{IconBounds::FILE.relative_path_from(Rails.root)}"
  end
end
