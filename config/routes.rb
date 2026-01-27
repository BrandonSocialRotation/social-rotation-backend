Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Serve uploaded files from public/uploads directory
  # This allows images stored locally to be accessible via URL
  get "uploads/*path", to: proc { |env|
    path = env['action_dispatch.request.path_parameters'][:path]
    file_path = Rails.root.join('public', 'uploads', path).to_s
    
    headers = {
      'Content-Type' => Rack::Mime.mime_type(File.extname(file_path)),
      'Access-Control-Allow-Origin' => '*',
      'Access-Control-Allow-Methods' => 'GET, OPTIONS',
      'Access-Control-Allow-Headers' => 'Content-Type'
    }
    
    if File.exist?(file_path) && File.file?(file_path)
      [200, headers, [File.read(file_path)]]
    else
      [404, { 'Content-Type' => 'text/plain' }, ['File not found']]
    end
  }

  # API Routes
  namespace :api do
    namespace :v1 do
      # Legacy GET routes removed - using POST routes in resources block below
      get 'plans/index'
      get 'plans/show'
      # Analytics routes
      get 'analytics/instagram/summary', to: 'analytics#instagram_summary'
      get 'analytics/instagram/timeseries', to: 'analytics#instagram_timeseries'
      get 'analytics/platform/:platform', to: 'analytics#platform_analytics'
      get 'analytics/overall', to: 'analytics#overall'
      get 'analytics/posts_count', to: 'analytics#posts_count'
      get 'sub_accounts/index'
      get 'sub_accounts/create'
      get 'sub_accounts/show'
      get 'sub_accounts/update'
      get 'sub_accounts/destroy'
      get 'sub_accounts/switch'
      # Authentication routes
      post 'auth/login', to: 'auth#login'
      post 'auth/register', to: 'auth#register'
      post 'auth/logout', to: 'auth#logout'
      post 'auth/refresh', to: 'auth#refresh'
      post 'auth/forgot_password', to: 'auth#forgot_password'
      post 'auth/reset_password', to: 'auth#reset_password'
      
      # OAuth routes
      get 'oauth/facebook/login', to: 'oauth#facebook_login'
      get 'oauth/facebook/callback', to: 'oauth#facebook_callback'
      get 'oauth/instagram/login', to: 'oauth#instagram_login'
      get 'oauth/instagram/callback', to: 'oauth#instagram_callback'
      get 'oauth/instagram/connect', to: 'oauth#instagram_connect'
      get 'oauth/twitter/login', to: 'oauth#twitter_login'
      get 'oauth/twitter/callback', to: 'oauth#twitter_callback'
      get 'oauth/linkedin/login', to: 'oauth#linkedin_login'
      get 'oauth/linkedin/callback', to: 'oauth#linkedin_callback'
      get 'oauth/google/login', to: 'oauth#google_login'
      get 'oauth/google/callback', to: 'oauth#google_callback'
      get 'oauth/test_google', to: 'oauth#test_google'
      get 'oauth/tiktok/login', to: 'oauth#tiktok_login'
      get 'oauth/tiktok/callback', to: 'oauth#tiktok_callback'
      get 'oauth/youtube/login', to: 'oauth#youtube_login'
      get 'oauth/youtube/callback', to: 'oauth#youtube_callback'
      get 'oauth/pinterest/login', to: 'oauth#pinterest_login'
      get 'oauth/pinterest/callback', to: 'oauth#pinterest_callback'

      # User info routes
      get 'user_info', to: 'user_info#show'
      get 'user_info/debug', to: 'user_info#debug'
      patch 'user_info', to: 'user_info#update'
      get 'user_info/support', to: 'user_info#support'
      post 'user_info/watermark', to: 'user_info#update_watermark'
      get 'user_info/connected_accounts', to: 'user_info#connected_accounts'
      post 'user_info/disconnect_facebook', to: 'user_info#disconnect_facebook'
      post 'user_info/disconnect_twitter', to: 'user_info#disconnect_twitter'
      post 'user_info/disconnect_linkedin', to: 'user_info#disconnect_linkedin'
      post 'user_info/disconnect_instagram', to: 'user_info#disconnect_instagram'
      post 'user_info/disconnect_google', to: 'user_info#disconnect_google'
      post 'user_info/disconnect_tiktok', to: 'user_info#disconnect_tiktok'
      post 'user_info/disconnect_youtube', to: 'user_info#disconnect_youtube'
      post 'user_info/toggle_instagram', to: 'user_info#toggle_instagram'
      post 'user_info/convert_to_agency', to: 'user_info#convert_to_agency'
      delete 'user_info/delete_test_account', to: 'user_info#delete_test_account'
      get 'user_info/watermark_preview', to: 'user_info#watermark_preview'
      get 'user_info/standard_preview', to: 'user_info#standard_preview'
      get 'user_info/facebook_pages', to: 'user_info#facebook_pages'
      get 'user_info/linkedin_organizations', to: 'user_info#linkedin_organizations'

      # Bucket routes
      resources :buckets do
        member do
          get 'page/:page_num', to: 'buckets#page'
          get 'images', to: 'buckets#images'
          post 'images', to: 'buckets#add_image'
          post 'images/upload', to: 'buckets#upload_image'
          get 'images/:image_id', to: 'buckets#single_image'
          patch 'images/:image_id', to: 'buckets#update_image'
          delete 'images/:image_id', to: 'buckets#delete_image'
          get 'videos', to: 'buckets#videos'
          post 'videos/upload', to: 'buckets#upload_video'
          get 'randomize', to: 'buckets#randomize'
        end
        collection do
          get 'for_scheduling', to: 'buckets#for_scheduling'
        end
      end

      # Bucket schedule routes
      resources :bucket_schedules do
        member do
          post 'post_now', to: 'bucket_schedules#post_now'
          post 'skip_image', to: 'bucket_schedules#skip_image'
          post 'skip_image_single', to: 'bucket_schedules#skip_image_single'
          get 'history', to: 'bucket_schedules#history'
          get 'diagnose', to: 'bucket_schedules#diagnose'
        end
        collection do
          post 'bulk_update', to: 'bucket_schedules#bulk_update'
          delete 'bulk_delete', to: 'bucket_schedules#bulk_delete'
          post 'rotation_create', to: 'bucket_schedules#rotation_create'
          post 'date_create', to: 'bucket_schedules#date_create'
        end
        resources :schedule_items, only: [:create, :update, :destroy]
      end

      # Scheduler routes
      post 'scheduler/single_post', to: 'scheduler#single_post'
      post 'scheduler/schedule', to: 'scheduler#schedule'
      post 'scheduler/post_now/:id', to: 'scheduler#post_now'
      post 'scheduler/skip_image/:id', to: 'scheduler#skip_image'
      post 'scheduler/skip_image_single/:id', to: 'scheduler#skip_image_single'
      get 'scheduler/open_graph', to: 'scheduler#open_graph'
      post 'scheduler/process_now', to: 'scheduler#process_now' # Manual trigger for testing

      # Sub-account management routes
      resources :sub_accounts, only: [:index, :create, :show, :update, :destroy] do
        collection do
          post 'switch/:id', to: 'sub_accounts#switch'
        end
      end
      
      # Account management routes
      get 'account/features', to: 'accounts#features'
      patch 'account/features', to: 'accounts#update_features'
      
      # Plan management routes
      resources :plans, only: [:index, :show]
      
      # Subscription routes
      resources :subscriptions, only: [:index, :show, :create] do
        collection do
          get 'test_stripe', to: 'subscriptions#test_stripe'
          get 'run_migrations', to: 'subscriptions#run_migrations' # Temporary endpoint to run pending migrations
          post 'checkout_session', to: 'subscriptions#checkout_session'
          post 'checkout_session_for_pending', to: 'subscriptions#checkout_session_for_pending'
          post 'cancel', to: 'subscriptions#cancel'
          post 'webhook', to: 'subscriptions#webhook'
        end
      end

      # Image management routes
      resources :images, only: [:create] do
        collection do
          get 'proxy', to: 'images#proxy'
          options 'proxy', to: 'images#proxy_options'
        end
      end

      # RSS feed management routes
      resources :rss_feeds, only: [:index, :create, :show, :update, :destroy] do
        collection do
          post :validate
          post :fetch_all
        end
        member do
          post :fetch_posts
          get :posts
        end
      end

      # RSS posts management routes
      resources :rss_posts, only: [:index, :show, :update] do
        member do
          post :mark_viewed
          post :mark_unviewed
          post :schedule_post
        end
        collection do
          get :unviewed
          get :recent
          post :bulk_mark_viewed
          post :bulk_mark_unviewed
        end
      end
      
      # Marketplace routes
      resources :marketplace, only: [:index, :show] do
        member do
          get 'info', to: 'marketplace#info'
          post 'clone', to: 'marketplace#clone'
          post 'copy_to_bucket', to: 'marketplace#copy_to_bucket'
          post 'buy', to: 'marketplace#buy'
          post 'hide', to: 'marketplace#hide'
          post 'make_visible', to: 'marketplace#make_visible'
        end
        collection do
          get 'available', to: 'marketplace#available'
          get 'user_buckets', to: 'marketplace#user_buckets'
        end
      end
    end
  end

  # Stripe webhook endpoint (legacy path that Stripe is configured to use)
  post 'stripe/subscription_created', to: 'api/v1/subscriptions#webhook'
  
  # Privacy policy route (for Meta/Facebook verification)
  get "privacy-policy", to: "privacy#show"
  
  # Defines the root path route ("/")
  root "health#show"
end
