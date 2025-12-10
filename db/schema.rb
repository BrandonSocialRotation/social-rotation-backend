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

ActiveRecord::Schema[7.1].define(version: 2025_12_10_183345) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "account_features", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.boolean "allow_marketplace", default: true
    t.boolean "allow_rss", default: true
    t.boolean "allow_integrations", default: true
    t.boolean "allow_watermark", default: true
    t.integer "max_users", default: 1
    t.integer "max_buckets", default: 10
    t.integer "max_images_per_bucket", default: 100
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_account_features_on_account_id"
  end

  create_table "accounts", force: :cascade do |t|
    t.string "name", null: false
    t.string "subdomain"
    t.string "top_level_domain"
    t.boolean "is_reseller", default: false
    t.boolean "status", default: true
    t.string "support_email"
    t.text "terms_conditions"
    t.text "privacy_policy"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "plan_id"
    t.index ["plan_id"], name: "index_accounts_on_plan_id"
    t.index ["subdomain"], name: "index_accounts_on_subdomain", unique: true
  end

  create_table "bucket_images", force: :cascade do |t|
    t.bigint "bucket_id", null: false
    t.bigint "image_id", null: false
    t.string "friendly_name"
    t.text "description"
    t.text "twitter_description"
    t.datetime "force_send_date"
    t.boolean "repeat"
    t.integer "post_to"
    t.boolean "use_watermark"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "facebook_page_id"
    t.string "linkedin_organization_urn"
    t.index ["bucket_id"], name: "index_bucket_images_on_bucket_id"
    t.index ["image_id"], name: "index_bucket_images_on_image_id"
  end

  create_table "bucket_schedules", force: :cascade do |t|
    t.bigint "bucket_id", null: false
    t.bigint "bucket_image_id"
    t.string "schedule"
    t.datetime "schedule_time"
    t.integer "post_to"
    t.integer "schedule_type"
    t.text "description"
    t.text "twitter_description"
    t.integer "times_sent"
    t.integer "skip_image"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bucket_id"], name: "index_bucket_schedules_on_bucket_id"
    t.index ["bucket_image_id"], name: "index_bucket_schedules_on_bucket_image_id"
  end

  create_table "bucket_send_histories", force: :cascade do |t|
    t.bigint "bucket_id", null: false
    t.bigint "bucket_schedule_id", null: false
    t.bigint "bucket_image_id", null: false
    t.string "friendly_name"
    t.text "text"
    t.text "twitter_text"
    t.integer "sent_to"
    t.datetime "sent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bucket_id"], name: "index_bucket_send_histories_on_bucket_id"
    t.index ["bucket_image_id"], name: "index_bucket_send_histories_on_bucket_image_id"
    t.index ["bucket_schedule_id"], name: "index_bucket_send_histories_on_bucket_schedule_id"
  end

  create_table "bucket_videos", force: :cascade do |t|
    t.bigint "bucket_id", null: false
    t.bigint "video_id", null: false
    t.string "friendly_name"
    t.text "description"
    t.text "twitter_description"
    t.integer "post_to"
    t.boolean "use_watermark", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bucket_id", "video_id"], name: "index_bucket_videos_on_bucket_id_and_video_id", unique: true
    t.index ["bucket_id"], name: "index_bucket_videos_on_bucket_id"
    t.index ["video_id"], name: "index_bucket_videos_on_video_id"
  end

  create_table "buckets", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.bigint "user_id", null: false
    t.integer "account_id"
    t.boolean "use_watermark"
    t.boolean "post_once_bucket"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_buckets_on_user_id"
  end

  create_table "images", force: :cascade do |t|
    t.string "file_path"
    t.string "friendly_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "market_items", force: :cascade do |t|
    t.bigint "bucket_id", null: false
    t.bigint "front_image_id"
    t.decimal "price"
    t.boolean "visible"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bucket_id"], name: "index_market_items_on_bucket_id"
    t.index ["front_image_id"], name: "index_market_items_on_front_image_id"
  end

  create_table "oauth_request_tokens", force: :cascade do |t|
    t.string "oauth_token"
    t.string "request_secret"
    t.integer "user_id"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_oauth_request_tokens_on_expires_at"
    t.index ["oauth_token"], name: "index_oauth_request_tokens_on_oauth_token", unique: true
  end

  create_table "plans", force: :cascade do |t|
    t.string "name", null: false
    t.string "plan_type", null: false
    t.string "stripe_price_id"
    t.string "stripe_product_id"
    t.integer "price_cents", default: 0
    t.integer "max_locations", default: 1
    t.integer "max_users", default: 1
    t.integer "max_buckets", default: 10
    t.integer "max_images_per_bucket", default: 100
    t.text "features"
    t.boolean "status", default: true
    t.integer "sort_order", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "base_price_cents", default: 0
    t.integer "per_user_price_cents", default: 0
    t.integer "per_user_price_after_10_cents", default: 0
    t.string "billing_period", default: "monthly"
    t.boolean "supports_per_user_pricing", default: false
    t.index ["plan_type"], name: "index_plans_on_plan_type"
    t.index ["status"], name: "index_plans_on_status"
    t.index ["stripe_price_id"], name: "index_plans_on_stripe_price_id", unique: true
  end

  create_table "rss_feeds", force: :cascade do |t|
    t.string "url", null: false
    t.string "name", null: false
    t.text "description"
    t.integer "account_id"
    t.integer "user_id", null: false
    t.boolean "is_active", default: true
    t.datetime "last_fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "last_fetch_error"
    t.integer "fetch_failure_count"
    t.datetime "last_successful_fetch_at"
    t.index ["account_id"], name: "index_rss_feeds_on_account_id"
    t.index ["is_active"], name: "index_rss_feeds_on_is_active"
    t.index ["url"], name: "index_rss_feeds_on_url"
    t.index ["user_id"], name: "index_rss_feeds_on_user_id"
  end

  create_table "rss_posts", force: :cascade do |t|
    t.integer "rss_feed_id", null: false
    t.string "title", null: false
    t.text "description"
    t.text "content"
    t.string "image_url"
    t.string "original_url"
    t.datetime "published_at", null: false
    t.boolean "is_viewed", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["is_viewed"], name: "index_rss_posts_on_is_viewed"
    t.index ["published_at"], name: "index_rss_posts_on_published_at"
    t.index ["rss_feed_id", "published_at"], name: "index_rss_posts_on_rss_feed_id_and_published_at"
    t.index ["rss_feed_id"], name: "index_rss_posts_on_rss_feed_id"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "stripe_subscription_id"
    t.string "stripe_customer_id"
    t.bigint "plan_id", null: false
    t.string "status", default: "active"
    t.datetime "current_period_start"
    t.datetime "current_period_end"
    t.boolean "cancel_at_period_end", default: false
    t.datetime "canceled_at"
    t.datetime "trial_end"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "billing_period", default: "monthly"
    t.integer "user_count_at_subscription"
    t.index ["account_id"], name: "index_subscriptions_on_account_id"
    t.index ["plan_id"], name: "index_subscriptions_on_plan_id"
    t.index ["status"], name: "index_subscriptions_on_status"
    t.index ["stripe_customer_id"], name: "index_subscriptions_on_stripe_customer_id"
    t.index ["stripe_subscription_id"], name: "index_subscriptions_on_stripe_subscription_id", unique: true
  end

  create_table "user_market_items", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "market_item_id", null: false
    t.boolean "visible"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["market_item_id"], name: "index_user_market_items_on_market_item_id"
    t.index ["user_id"], name: "index_user_market_items_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email"
    t.string "password_digest"
    t.string "name"
    t.string "timezone"
    t.string "watermark_logo"
    t.decimal "watermark_scale"
    t.integer "watermark_opacity"
    t.integer "watermark_offset_x"
    t.integer "watermark_offset_y"
    t.integer "account_id", default: 0
    t.text "fb_user_access_key"
    t.string "instagram_business_id"
    t.text "twitter_oauth_token"
    t.text "twitter_oauth_token_secret"
    t.string "twitter_user_id"
    t.string "twitter_screen_name"
    t.text "linkedin_access_token"
    t.datetime "linkedin_access_token_time"
    t.string "linkedin_profile_id"
    t.text "google_refresh_token"
    t.string "location_id"
    t.boolean "post_to_instagram"
    t.string "twitter_url_oauth_token"
    t.string "twitter_url_oauth_token_secret"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "tiktok_access_token"
    t.string "tiktok_refresh_token"
    t.string "tiktok_user_id"
    t.string "tiktok_username"
    t.string "youtube_access_token"
    t.string "youtube_refresh_token"
    t.string "youtube_channel_id"
    t.boolean "is_account_admin", default: false
    t.integer "status", default: 1
    t.string "role", default: "user"
    t.string "pinterest_access_token"
    t.string "pinterest_refresh_token"
    t.string "facebook_name"
    t.string "google_account_name"
    t.string "pinterest_username"
    t.string "youtube_channel_name"
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "videos", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "file_path"
    t.string "friendly_name"
    t.integer "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_videos_on_user_id"
  end

  add_foreign_key "account_features", "accounts"
  add_foreign_key "accounts", "plans"
  add_foreign_key "bucket_images", "buckets"
  add_foreign_key "bucket_images", "images"
  add_foreign_key "bucket_schedules", "bucket_images"
  add_foreign_key "bucket_schedules", "buckets"
  add_foreign_key "bucket_send_histories", "bucket_images"
  add_foreign_key "bucket_send_histories", "bucket_schedules"
  add_foreign_key "bucket_send_histories", "buckets"
  add_foreign_key "bucket_videos", "buckets"
  add_foreign_key "bucket_videos", "videos"
  add_foreign_key "buckets", "users"
  add_foreign_key "market_items", "buckets"
  add_foreign_key "market_items", "images", column: "front_image_id"
  add_foreign_key "subscriptions", "accounts"
  add_foreign_key "subscriptions", "plans"
  add_foreign_key "user_market_items", "market_items"
  add_foreign_key "user_market_items", "users"
  add_foreign_key "videos", "users"
end
