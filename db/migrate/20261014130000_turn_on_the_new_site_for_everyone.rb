# Every account gets the new site. Each account turned on here gets an audit
# event new_site.on marked everyone, so the down step turns off only those.
# A browser that switched back to the old desktop keeps its classic cookie.
class TurnOnTheNewSiteForEveryone < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      INSERT INTO audit_events (action, subject_type, subject_id, data, created_at)
      SELECT 'new_site.on', 'User', id, '{"everyone": true}'::jsonb, NOW() FROM users WHERE new_site = false
    SQL
    execute "UPDATE users SET new_site = true WHERE new_site = false"
  end

  def down
    execute <<~SQL
      UPDATE users SET new_site = false
      WHERE id IN (SELECT subject_id FROM audit_events WHERE action = 'new_site.on' AND subject_type = 'User' AND data ->> 'everyone' = 'true')
    SQL
    execute "DELETE FROM audit_events WHERE action = 'new_site.on' AND data ->> 'everyone' = 'true'"
  end
end
