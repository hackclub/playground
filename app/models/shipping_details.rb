# The name and address a goal ships to. Prefilled from Hack Club Auth and
# fully editable, like a shop checkout: the name on the parcel can differ from
# the account name (for example someone not out at home). Whatever the
# participant confirms is frozen onto the redemption; nothing else uses it.
class ShippingDetails
  include ActiveModel::Model
  include ActiveModel::Attributes

  FIELDS = %i[first_name last_name line_1 line_2 city state postal_code country phone_number].freeze
  FIELDS.each { attribute it, :string }

  validates :first_name, :line_1, :city, :country, presence: true
  validates(*FIELDS, length: { maximum: 120 })
  validates :phone_number, format: { with: /\A[+\d\s().-]{5,30}\z/, message: "should be digits, spaces, and + ( ) -" }, allow_blank: true

  def self.from_hca(address)
    new(address.to_h.slice(*FIELDS.map(&:to_s)))
  end

  # One line each: newlines and control characters would break labels.
  def self.from_params(params)
    new(params.permit(*FIELDS).to_h.transform_values { it.to_s.gsub(/[[:cntrl:]]/, " ").squeeze(" ").strip })
  end

  def to_h = attributes.transform_values(&:presence).compact
end
