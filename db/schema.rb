# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_07_200000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "audit_events", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_id"
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.bigint "subject_id"
    t.string "subject_type"
    t.index ["actor_id"], name: "index_audit_events_on_actor_id"
    t.index ["subject_type", "subject_id"], name: "index_audit_events_on_subject"
  end

  create_table "claims", force: :cascade do |t|
    t.bigint "claimable_id", null: false
    t.string "claimable_type", null: false
    t.datetime "created_at", null: false
    t.datetime "heartbeat_at", null: false
    t.string "stage", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["claimable_type", "claimable_id", "stage"], name: "index_claims_on_claimable_type_and_claimable_id_and_stage", unique: true
    t.index ["claimable_type", "claimable_id"], name: "index_claims_on_claimable"
    t.index ["user_id"], name: "index_claims_on_user_id"
  end

  create_table "coding_hours", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "hour", null: false
    t.integer "seconds", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["hour"], name: "index_coding_hours_on_hour"
    t.index ["user_id", "hour"], name: "index_coding_hours_on_user_id_and_hour", unique: true
    t.check_constraint "hour = date_trunc('hour'::text, hour)", name: "coding_hours_hour_is_whole"
    t.check_constraint "seconds >= 0 AND seconds <= 3600", name: "coding_hours_seconds_fit_the_hour"
  end

  create_table "nps_responses", force: :cascade do |t|
    t.text "anything_else"
    t.datetime "created_at", null: false
    t.text "doing_well"
    t.text "improve"
    t.bigint "project_id"
    t.integer "score", null: false
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["created_at"], name: "index_nps_responses_on_created_at"
    t.index ["project_id"], name: "index_nps_responses_on_project_id"
    t.index ["user_id", "created_at"], name: "index_nps_responses_on_user_id_and_created_at"
    t.check_constraint "score >= 0 AND score <= 10", name: "nps_responses_score_0_to_10"
  end

  create_table "projects", force: :cascade do |t|
    t.string "code_url"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "hackatime_projects", default: [], null: false, array: true
    t.string "name", null: false
    t.string "playable_url"
    t.jsonb "screenshots", default: [], null: false
    t.string "ship_message_url"
    t.datetime "tracked_at"
    t.integer "tracked_seconds", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_projects_on_user_id"
  end

  create_table "redemptions", force: :cascade do |t|
    t.text "address"
    t.string "airtable_record_id"
    t.integer "cost_cents"
    t.datetime "created_at", null: false
    t.datetime "fulfilled_at"
    t.bigint "fulfilled_by_id"
    t.string "goal_key", null: false
    t.text "notes"
    t.string "status", default: "pending", null: false
    t.datetime "synced_at"
    t.string "tracking"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["fulfilled_by_id"], name: "index_redemptions_on_fulfilled_by_id"
    t.index ["status", "created_at"], name: "index_redemptions_on_status_and_created_at"
    t.index ["user_id", "goal_key"], name: "index_redemptions_on_user_id_and_goal_key", unique: true
    t.index ["user_id"], name: "index_redemptions_on_user_id"
  end

  create_table "ships", force: :cascade do |t|
    t.string "airtable_record_id"
    t.integer "approved_seconds"
    t.integer "claimed_seconds", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "fraud_deduction_seconds", default: 0, null: false
    t.text "fraud_notes"
    t.datetime "fraud_reviewed_at"
    t.bigint "fraud_reviewer_id"
    t.string "fraud_status", default: "waiting", null: false
    t.boolean "in_unified", default: false, null: false
    t.bigint "project_id", null: false
    t.jsonb "review_checklist", default: {}, null: false
    t.text "review_feedback"
    t.text "review_judgement"
    t.integer "review_seconds"
    t.string "review_status", default: "pending", null: false
    t.datetime "reviewed_at"
    t.bigint "reviewer_id"
    t.jsonb "snapshot", default: {}, null: false
    t.string "state", default: "pending", null: false
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["fraud_reviewer_id"], name: "index_ships_on_fraud_reviewer_id"
    t.index ["fraud_status", "reviewed_at"], name: "index_ships_on_fraud_status_and_reviewed_at"
    t.index ["project_id"], name: "index_ships_on_project_id"
    t.index ["review_status", "created_at"], name: "index_ships_on_review_status_and_created_at"
    t.index ["reviewer_id"], name: "index_ships_on_reviewer_id"
    t.index ["synced_at"], name: "index_ships_on_synced_at"
    t.index ["user_id"], name: "index_ships_on_user_id"
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.bigint "channel_hash", null: false
    t.datetime "created_at", null: false
    t.binary "payload", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "key", null: false
    t.bigint "key_hash", null: false
    t.binary "value", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_batch_executions", force: :cascade do |t|
    t.bigint "batch_id", null: false
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.index ["batch_id"], name: "index_solid_queue_batch_executions_on_batch_id"
    t.index ["job_id"], name: "index_solid_queue_batch_executions_on_job_id", unique: true
  end

  create_table "solid_queue_batches", force: :cascade do |t|
    t.string "active_job_batch_id"
    t.integer "completed_jobs", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.datetime "enqueued_at"
    t.datetime "failed_at"
    t.integer "failed_jobs", default: 0, null: false
    t.datetime "finished_at"
    t.text "metadata"
    t.text "on_failure"
    t.text "on_finish"
    t.text "on_success"
    t.integer "total_jobs", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_batch_id"], name: "index_solid_queue_batches_on_active_job_batch_id", unique: true
    t.index ["finished_at"], name: "index_solid_queue_batches_on_finished_at"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.bigint "batch_id"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["batch_id"], name: "index_solid_queue_jobs_on_batch_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "address_synced_at"
    t.boolean "admin", default: false, null: false
    t.string "airtable_record_id"
    t.string "ban_reason"
    t.boolean "banana_peel_out", default: false, null: false
    t.datetime "banned_at"
    t.date "birthday"
    t.datetime "coding_hours_synced_at"
    t.datetime "created_at", null: false
    t.string "desktop_trash", default: ["banana peel"], null: false, array: true
    t.string "display_name"
    t.string "display_name_source"
    t.string "email"
    t.string "first_name"
    t.datetime "first_pet_created_at"
    t.text "hackatime_access_token"
    t.string "hackatime_trust_level"
    t.string "hackatime_user_id"
    t.text "hca_access_token"
    t.string "hca_id", null: false
    t.text "hca_refresh_token"
    t.string "last_name"
    t.boolean "new_site", default: false, null: false
    t.datetime "no_time_nudge_at"
    t.integer "session_version", default: 0, null: false
    t.string "slack_id"
    t.datetime "slack_invited_at"
    t.datetime "slack_prompt_dismissed_at"
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.string "verification_status"
    t.boolean "ysws_eligible", default: false, null: false
    t.index ["hca_id"], name: "index_users_on_hca_id", unique: true
    t.index ["synced_at"], name: "index_users_on_synced_at"
  end

  add_foreign_key "audit_events", "users", column: "actor_id"
  add_foreign_key "claims", "users"
  add_foreign_key "coding_hours", "users"
  add_foreign_key "nps_responses", "projects", on_delete: :nullify
  add_foreign_key "nps_responses", "users", on_delete: :cascade
  add_foreign_key "projects", "users"
  add_foreign_key "redemptions", "users"
  add_foreign_key "redemptions", "users", column: "fulfilled_by_id"
  add_foreign_key "ships", "projects"
  add_foreign_key "ships", "users"
  add_foreign_key "ships", "users", column: "fraud_reviewer_id"
  add_foreign_key "ships", "users", column: "reviewer_id"
  add_foreign_key "solid_queue_batch_executions", "solid_queue_batches", column: "batch_id", on_delete: :cascade
  add_foreign_key "solid_queue_batch_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
end
