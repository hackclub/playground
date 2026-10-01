# Writes screenshots to the Hack Club R2 bucket. With
# no R2 keys in the credentials, uploads refuse; nothing is saved anywhere
# else. Tests swap in an in-memory store through ScreenshotStore.current=.
class ScreenshotStore
  class NotConfigured < StandardError; end

  class << self
    attr_writer :current
    def current = @current ||= new
  end

  def configured? = creds.values_at(:endpoint, :access_key_id, :secret_access_key).all?(&:present?)

  def put(key, bytes)
    raise NotConfigured, "screenshot storage isn't set up yet" unless configured?
    client.put_object(bucket: config[:bucket], key:, body: bytes, content_type: "image/webp",
                      cache_control: "public, max-age=31536000, immutable")
    url(key)
  end

  def delete(key)
    return unless configured? && key.present?
    client.delete_object(bucket: config[:bucket], key:)
  end

  def url(key) = "https://#{config[:public_host]}/#{key}"

  private

  def config = Rails.application.config_for(:r2)
  def creds = Rails.application.credentials.r2 || {}

  def client
    require "aws-sdk-s3"
    @client ||= Aws::S3::Client.new(endpoint: creds[:endpoint], region: "auto",
                                    access_key_id: creds[:access_key_id], secret_access_key: creds[:secret_access_key])
  end
end
