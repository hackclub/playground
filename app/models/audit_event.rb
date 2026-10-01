class AuditEvent < ApplicationRecord
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :subject, polymorphic: true, optional: true

  def self.record(actor, subject, action, **data)
    create!(actor: actor, subject: subject, action: action, data: data)
  end
end
