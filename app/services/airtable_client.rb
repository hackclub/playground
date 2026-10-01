# The smallest Airtable client the sync needs: batch upsert and a keyed
# lookup. Merges on a text field so a retry never makes a second row.
# Airtable allows 10 records a request and 5 requests a second per base.
class AirtableClient
  API = "https://api.airtable.com/v0"
  BATCH = 10

  def initialize(token: Rails.application.credentials.dig(:airtable, :program_token), base: Rails.application.config_for(:airtable)[:base])
    raise ArgumentError, "airtable.program_token is not set" if token.blank?
    @token = token
    @base = base
  end

  # rows: array of field hashes. Returns { merge value => record }.
  def upsert(table, rows, merge_on:)
    rows.each_slice(BATCH).each_with_object({}) do |slice, out|
      _, body = HttpJson.request(:patch, url(table), headers: auth, timeout: 20, json: {
        performUpsert: { fieldsToMergeOn: [ merge_on ] }, typecast: true, records: slice.map { { fields: it } }
      })
      body.fetch("records").each { out[it.dig("fields", merge_on).to_s] = it }
    end
  end

  # Records whose merge field matches one of the values.
  def find_by(table, field, values)
    return {} if values.empty?
    formula = "OR(" + values.map { "{#{field}}='#{it.to_s.gsub("'", "\\\\'")}'" }.join(",") + ")"
    body = HttpJson.get("#{url(table)}?#{{ filterByFormula: formula, pageSize: 100 }.to_query}", headers: auth)
    body.fetch("records").to_h { [ it.dig("fields", field).to_s, it ] }
  end

  private

  def url(table) = "#{API}/#{@base}/#{ERB::Util.url_encode(table)}"
  def auth = { "Authorization" => "Bearer #{@token}" }
end
