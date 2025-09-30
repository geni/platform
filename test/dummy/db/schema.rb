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

ActiveRecord::Schema[8.0].define(version: 2025_09_30_142938) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "platform_application_categories", id: :serial, force: :cascade do |t|
    t.integer "category_id", null: false
    t.integer "application_id", null: false
    t.integer "position"
    t.boolean "featured"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["category_id", "application_id"], name: "idx_platform_app_categories_on_cat_and_app"
    t.index ["category_id"], name: "index_platform_application_categories_on_category_id"
  end

  create_table "platform_application_developers", id: :serial, force: :cascade do |t|
    t.integer "application_id"
    t.integer "developer_id"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["application_id"], name: "index_platform_application_developers_on_application_id"
    t.index ["developer_id"], name: "index_platform_application_developers_on_developer_id"
  end

  create_table "platform_application_logs", id: :serial, force: :cascade do |t|
    t.integer "application_id"
    t.integer "user_id"
    t.string "event"
    t.string "controller"
    t.string "action"
    t.string "request_method"
    t.text "data"
    t.string "user_agent"
    t.integer "duration"
    t.string "host"
    t.string "country"
    t.string "ip"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["application_id", "created_at"], name: "idx_platform_application_logs_on_app_and_created_at"
  end

  create_table "platform_application_metrics", id: :serial, force: :cascade do |t|
    t.string "type"
    t.datetime "interval", precision: nil
    t.integer "application_id"
    t.integer "active_user_count"
    t.integer "new_user_count"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["application_id", "interval"], name: "idx_platform_application_metrics_on_app_and_interval"
  end

  create_table "platform_application_permissions", id: :serial, force: :cascade do |t|
    t.integer "application_id"
    t.integer "permission_id"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["application_id"], name: "index_platform_application_permissions_on_application_id"
  end

  create_table "platform_application_usage_metrics", id: :serial, force: :cascade do |t|
    t.string "type"
    t.datetime "interval", precision: nil
    t.integer "application_id"
    t.string "event"
    t.integer "count"
    t.integer "avg_response_time"
    t.integer "error_count"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["application_id", "interval"], name: "idx_platform_app_usage_metrics_on_app_and_interval"
  end

  create_table "platform_application_users", id: :serial, force: :cascade do |t|
    t.integer "application_id", null: false
    t.integer "user_id", null: false
    t.text "data"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["application_id"], name: "index_platform_application_users_on_application_id"
    t.index ["user_id"], name: "index_platform_application_users_on_user_id"
  end

  create_table "platform_applications", id: :serial, force: :cascade do |t|
    t.integer "developer_id"
    t.string "name"
    t.text "description"
    t.string "state", default: "new"
    t.string "locale"
    t.string "url"
    t.string "site_domain"
    t.string "support_url"
    t.string "callback_url"
    t.string "contact_email"
    t.string "privacy_policy_url"
    t.string "terms_of_service_url"
    t.string "permissions"
    t.string "key"
    t.string "secret"
    t.integer "icon_id"
    t.integer "logo_id"
    t.string "canvas_name"
    t.string "canvas_url"
    t.boolean "auto_resize"
    t.boolean "auto_login"
    t.string "mobile_application_type"
    t.string "ios_bundle_id"
    t.string "itunes_app_store_id"
    t.string "android_key_hash"
    t.integer "rank"
    t.boolean "auto_signin"
    t.string "deauthorize_callback_url"
    t.string "version"
    t.string "api_version"
    t.integer "parent_id"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.text "consent_label"
    t.index ["developer_id"], name: "index_platform_applications_on_developer_id"
    t.index ["key"], name: "index_platform_applications_on_key", unique: true
    t.index ["parent_id"], name: "index_platform_applications_on_parent_id"
  end

  create_table "platform_categories", id: :serial, force: :cascade do |t|
    t.string "type"
    t.string "name"
    t.string "keyword"
    t.integer "position"
    t.date "enable_on"
    t.date "disable_on"
    t.integer "parent_id"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["parent_id"], name: "index_platform_categories_on_parent_id"
  end

  create_table "platform_developers", id: :serial, force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.text "about"
    t.string "url"
    t.string "email"
    t.string "phone"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["user_id"], name: "index_platform_developers_on_user_id"
  end

  create_table "platform_forum_messages", id: :serial, force: :cascade do |t|
    t.integer "forum_topic_id", null: false
    t.integer "user_id", null: false
    t.text "message", null: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["forum_topic_id"], name: "index_platform_forum_messages_on_forum_topic_id"
    t.index ["user_id"], name: "index_platform_forum_messages_on_user_id"
  end

  create_table "platform_forum_topics", id: :serial, force: :cascade do |t|
    t.string "subject_type"
    t.integer "subject_id"
    t.integer "user_id", null: false
    t.text "topic", null: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["subject_type", "subject_id"], name: "index_platform_forum_topics_on_subject_type_and_subject_id"
    t.index ["user_id"], name: "index_platform_forum_topics_on_user_id"
  end

  create_table "platform_logged_exceptions", id: :serial, force: :cascade do |t|
    t.string "exception_class"
    t.string "controller_name"
    t.string "action_name"
    t.string "server"
    t.text "message"
    t.text "backtrace"
    t.text "environment"
    t.text "request"
    t.text "session"
    t.binary "cause"
    t.integer "user_id"
    t.integer "application_id"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
  end

  create_table "platform_media", id: :serial, force: :cascade do |t|
    t.string "type"
    t.string "file_location"
    t.string "content_type"
    t.string "file_name"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
  end

  create_table "platform_oauth_tokens", id: :serial, force: :cascade do |t|
    t.string "type"
    t.bigint "user_id"
    t.integer "application_id"
    t.string "token", limit: 50
    t.string "secret", limit: 50
    t.string "verifier", limit: 20
    t.string "callback_url"
    t.string "scope"
    t.datetime "valid_to", precision: nil
    t.datetime "authorized_at", precision: nil
    t.datetime "invalidated_at", precision: nil
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["token"], name: "index_platform_oauth_tokens_on_token", unique: true
  end

  create_table "platform_permissions", id: :serial, force: :cascade do |t|
    t.string "keyword", null: false
    t.text "description", null: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["keyword"], name: "index_platform_permissions_on_keyword"
  end

  create_table "platform_ratings", id: :serial, force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "object_type"
    t.integer "object_id"
    t.integer "value"
    t.text "comment"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["object_type", "object_id"], name: "index_platform_ratings_on_object_type_and_object_id"
    t.index ["user_id"], name: "index_platform_ratings_on_user_id"
  end

  create_table "platform_rollup_logs", id: :serial, force: :cascade do |t|
    t.datetime "interval", precision: nil
    t.datetime "started_at", precision: nil
    t.datetime "finished_at", precision: nil
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["interval"], name: "index_platform_rollup_logs_on_interval"
  end

  create_table "tr8n_glossary", id: :serial, force: :cascade do |t|
    t.string "keyword"
    t.text "description"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["keyword"], name: "index_tr8n_glossary_on_keyword"
  end

  create_table "tr8n_ip_locations", id: :serial, force: :cascade do |t|
    t.bigint "low"
    t.bigint "high"
    t.string "registry", limit: 20
    t.date "assigned"
    t.string "ctry", limit: 2
    t.string "cntry", limit: 3
    t.string "country", limit: 80
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["high"], name: "index_tr8n_ip_locations_on_high"
    t.index ["low"], name: "index_tr8n_ip_locations_on_low"
  end

  create_table "tr8n_language_case_rules", id: :serial, force: :cascade do |t|
    t.integer "language_case_id", null: false
    t.integer "language_id"
    t.integer "translator_id"
    t.text "definition", null: false
    t.integer "position"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["language_case_id"], name: "tr8n_lcr_case_id"
    t.index ["language_id"], name: "tr8n_lcr_lang_id"
    t.index ["translator_id"], name: "tr8n_lcr_translator_id"
  end

  create_table "tr8n_language_case_value_maps", id: :serial, force: :cascade do |t|
    t.string "keyword", null: false
    t.integer "language_id", null: false
    t.integer "translator_id"
    t.text "map"
    t.boolean "reported"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["keyword", "language_id"], name: "index_tr8n_language_case_value_maps_on_keyword_and_language_id"
    t.index ["translator_id"], name: "index_tr8n_language_case_value_maps_on_translator_id"
  end

  create_table "tr8n_language_cases", id: :serial, force: :cascade do |t|
    t.integer "language_id", null: false
    t.integer "translator_id"
    t.string "keyword"
    t.string "latin_name"
    t.string "native_name"
    t.text "description"
    t.string "application"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["language_id", "keyword"], name: "index_tr8n_language_cases_on_language_id_and_keyword"
    t.index ["language_id", "translator_id"], name: "index_tr8n_language_cases_on_language_id_and_translator_id"
    t.index ["language_id"], name: "index_tr8n_language_cases_on_language_id"
  end

  create_table "tr8n_language_forum_abuse_reports", id: :serial, force: :cascade do |t|
    t.integer "language_id", null: false
    t.integer "translator_id", null: false
    t.integer "language_forum_message_id", null: false
    t.string "reason"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["language_forum_message_id"], name: "tr8n_forum_reports_message_id"
    t.index ["language_id", "translator_id"], name: "tr8n_forum_reports_lang_id_translator_id"
    t.index ["language_id"], name: "tr8n_forum_reports_lang_id"
  end

  create_table "tr8n_language_forum_messages", id: :serial, force: :cascade do |t|
    t.integer "language_id", null: false
    t.integer "language_forum_topic_id", null: false
    t.integer "translator_id", null: false
    t.text "message", null: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["language_id", "language_forum_topic_id"], name: "tr8n_forum_msgs_lang_id_topic_id"
    t.index ["language_id"], name: "tr8n_forum_msgs_lang_id"
    t.index ["translator_id"], name: "tr8n_forums_msgs_translator_id"
  end

  create_table "tr8n_language_forum_topics", id: :serial, force: :cascade do |t|
    t.integer "translator_id", null: false
    t.integer "language_id"
    t.text "topic", null: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["language_id"], name: "tr8n_forum_topics_lang_id"
    t.index ["translator_id"], name: "tr8n_forum_topics_translator_id"
  end

  create_table "tr8n_language_metrics", id: :serial, force: :cascade do |t|
    t.string "type"
    t.integer "language_id", null: false
    t.date "metric_date"
    t.integer "user_count", default: 0
    t.integer "translator_count", default: 0
    t.integer "translation_count", default: 0
    t.integer "key_count", default: 0
    t.integer "locked_key_count", default: 0
    t.integer "translated_key_count", default: 0
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["created_at"], name: "index_tr8n_language_metrics_on_created_at"
    t.index ["language_id"], name: "index_tr8n_language_metrics_on_language_id"
  end

  create_table "tr8n_language_rules", id: :serial, force: :cascade do |t|
    t.integer "language_id", null: false
    t.integer "translator_id"
    t.string "type"
    t.text "definition"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["language_id", "translator_id"], name: "index_tr8n_language_rules_on_language_id_and_translator_id"
    t.index ["language_id"], name: "index_tr8n_language_rules_on_language_id"
  end

  create_table "tr8n_language_users", id: :serial, force: :cascade do |t|
    t.integer "language_id", null: false
    t.integer "user_id", null: false
    t.integer "translator_id"
    t.boolean "manager", default: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["created_at"], name: "index_tr8n_language_users_on_created_at"
    t.index ["language_id", "translator_id"], name: "index_tr8n_language_users_on_language_id_and_translator_id"
    t.index ["language_id", "user_id"], name: "index_tr8n_language_users_on_language_id_and_user_id"
    t.index ["updated_at"], name: "index_tr8n_language_users_on_updated_at"
    t.index ["user_id"], name: "index_tr8n_language_users_on_user_id"
  end

  create_table "tr8n_languages", id: :serial, force: :cascade do |t|
    t.string "locale", null: false
    t.string "english_name", null: false
    t.string "native_name"
    t.boolean "enabled"
    t.boolean "right_to_left"
    t.integer "completeness"
    t.integer "fallback_language_id"
    t.text "curse_words"
    t.integer "featured_index", default: 0
    t.string "google_key"
    t.string "facebook_key"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["locale"], name: "index_tr8n_languages_on_locale"
  end

  create_table "tr8n_translation_domains", id: :serial, force: :cascade do |t|
    t.string "name"
    t.string "description"
    t.integer "source_count", default: 0
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["name"], name: "index_tr8n_translation_domains_on_name", unique: true
  end

  create_table "tr8n_translation_key_comments", id: :serial, force: :cascade do |t|
    t.integer "language_id", null: false
    t.integer "translation_key_id", null: false
    t.integer "translator_id", null: false
    t.text "message", null: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["language_id", "translation_key_id"], name: "tr8n_tkey_msgs_lang_id_tkey_id"
    t.index ["language_id"], name: "tr8n_tkey_msgs_lang_id"
    t.index ["translator_id"], name: "tr8n_tkey_msgs_translator_id"
  end

  create_table "tr8n_translation_key_locks", id: :serial, force: :cascade do |t|
    t.integer "translation_key_id", null: false
    t.integer "language_id", null: false
    t.integer "translator_id"
    t.boolean "locked", default: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["translation_key_id", "language_id"], name: "tr8n_locks_key_id_lang_id"
  end

  create_table "tr8n_translation_key_sources", id: :serial, force: :cascade do |t|
    t.integer "translation_key_id", null: false
    t.integer "translation_source_id", null: false
    t.text "details"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["translation_key_id"], name: "tr8n_trans_keys_key_id"
    t.index ["translation_source_id"], name: "tr8n_trans_keys_source_id"
  end

  create_table "tr8n_translation_keys", id: :serial, force: :cascade do |t|
    t.string "type"
    t.string "key", null: false
    t.text "label", null: false
    t.text "description"
    t.datetime "verified_at", precision: nil
    t.integer "translation_count"
    t.boolean "admin"
    t.string "locale"
    t.integer "level", default: 0
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["key"], name: "index_tr8n_translation_keys_on_key", unique: true
  end

  create_table "tr8n_translation_sources", id: :serial, force: :cascade do |t|
    t.string "source"
    t.integer "translation_domain_id"
    t.integer "key_count", default: 0
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["source"], name: "tr8n_sources_source"
  end

  create_table "tr8n_translation_votes", id: :serial, force: :cascade do |t|
    t.integer "translation_id", null: false
    t.integer "translator_id", null: false
    t.integer "vote", null: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["translation_id", "translator_id"], name: "tr8n_trans_votes_trans_id_translator_id"
    t.index ["translator_id"], name: "tr8n_trans_votes_translator_id"
  end

  create_table "tr8n_translations", id: :serial, force: :cascade do |t|
    t.integer "translation_key_id", null: false
    t.integer "language_id", null: false
    t.integer "translator_id", null: false
    t.text "label", null: false
    t.integer "rank", default: 0
    t.bigint "approved_by_id"
    t.text "rules"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["created_at"], name: "tr8n_trans_created_at"
    t.index ["translation_key_id", "translator_id", "language_id"], name: "tr8n_trans_key_id_translator_id_lang_id"
    t.index ["translator_id"], name: "r8n_trans_translator_id"
  end

  create_table "tr8n_translator_following", id: :serial, force: :cascade do |t|
    t.integer "translator_id"
    t.integer "object_id"
    t.string "object_type"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["translator_id"], name: "index_tr8n_translator_following_on_translator_id"
  end

  create_table "tr8n_translator_logs", id: :serial, force: :cascade do |t|
    t.integer "translator_id"
    t.bigint "user_id"
    t.string "action"
    t.integer "action_level"
    t.string "reason"
    t.string "reference"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["created_at"], name: "index_tr8n_translator_logs_on_created_at"
    t.index ["translator_id"], name: "index_tr8n_translator_logs_on_translator_id"
    t.index ["user_id"], name: "index_tr8n_translator_logs_on_user_id"
  end

  create_table "tr8n_translator_metrics", id: :serial, force: :cascade do |t|
    t.integer "translator_id", null: false
    t.integer "language_id"
    t.integer "total_translations", default: 0
    t.integer "total_votes", default: 0
    t.integer "positive_votes", default: 0
    t.integer "negative_votes", default: 0
    t.integer "accepted_translations", default: 0
    t.integer "rejected_translations", default: 0
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["created_at"], name: "index_tr8n_translator_metrics_on_created_at"
    t.index ["translator_id", "language_id"], name: "index_tr8n_translator_metrics_on_translator_id_and_language_id"
    t.index ["translator_id"], name: "index_tr8n_translator_metrics_on_translator_id"
  end

  create_table "tr8n_translator_reports", id: :serial, force: :cascade do |t|
    t.integer "translator_id"
    t.string "state"
    t.integer "object_id"
    t.string "object_type"
    t.string "reason"
    t.text "comment"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["translator_id"], name: "index_tr8n_translator_reports_on_translator_id"
  end

  create_table "tr8n_translators", id: :serial, force: :cascade do |t|
    t.integer "user_id", null: false
    t.boolean "inline_mode", default: false
    t.boolean "blocked", default: false
    t.boolean "reported", default: false
    t.integer "fallback_language_id"
    t.integer "rank", default: 0
    t.string "name"
    t.string "gender"
    t.string "email"
    t.string "password"
    t.string "mugshot"
    t.string "link"
    t.string "locale"
    t.integer "level", default: 0
    t.integer "manager"
    t.string "last_ip"
    t.string "country_code"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["created_at"], name: "index_tr8n_translators_on_created_at"
    t.index ["email", "password"], name: "index_tr8n_translators_on_email_and_password"
    t.index ["email"], name: "index_tr8n_translators_on_email"
    t.index ["user_id"], name: "index_tr8n_translators_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name"
    t.string "gender"
    t.string "email"
    t.string "password"
    t.string "mugshot"
    t.string "link"
    t.string "locale"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email", "password"], name: "index_users_on_email_and_password"
    t.index ["email"], name: "index_users_on_email"
  end

  create_table "wf_filters", id: :serial, force: :cascade do |t|
    t.string "type"
    t.string "name"
    t.text "data"
    t.integer "user_id"
    t.string "model_class_name"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["user_id"], name: "index_wf_filters_on_user_id"
  end
end
