# The sync now sets "Automation - Submit to Unified YSWS" on a ship row. The
# approved ships already copied went without it, so each goes through the
# sync once more. A ship the Unified DB has taken stays out.
class ResyncApprovedShipsForUnifiedCheckbox < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE ships SET synced_at = NULL WHERE state = 'approved' AND in_unified = false"
  end

  def down
  end
end
