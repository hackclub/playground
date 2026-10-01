# A prize marked on the meter. Each participant redeems each goal once, when
# their approved hours reach it.
class Goal < Data.define(:key, :name, :hours, :image)
  def self.all
    @all ||= [
      new(key: "stickers", name: "stickersheet", hours: 2, image: "landing/stickysheet.png"),
      new(key: "keychain", name: "playground keychain", hours: 5, image: "landing/keychain.png"),
      new(key: "shirt", name: "shirt with every shipped pet", hours: 10, image: "landing/shirt.png")
    ].freeze
  end

  def self.find(key) = all.find { it.key == key }

  def seconds = hours * 3600
end
