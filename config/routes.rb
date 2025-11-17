Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # API Routes
  namespace :api do
    namespace :v1 do
      # Analytics (Instagram / Meta)
      get 'analytics/instagram/summary', to: 'analytics#instagram_summary'
      get 'analytics/instagram/timeseries', to: 'analytics#instagram_timeseries'
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
      
      # OAuth routes
      get 'oauth/facebook/login', to: 'oauth#facebook_login'
      get 'oauth/facebook/callback', to: 'oauth#facebook_callback'
      get 'oauth/twitter/login', to: 'oauth#twitter_login'
      get 'oauth/twitter/callback', to: 'oauth#twitter_callback'
      get 'oauth/linkedin/login', to: 'oauth#linkedin_login'
      get 'oauth/linkedin/callback', to: 'oauth#linkedin_callback'
      get 'oauth/google/login', to: 'oauth#google_login'
      get 'oauth/google/callback', to: 'oauth#google_callback'
      get 'oauth/tiktok/login', to: 'oauth#tiktok_login'
      get 'oauth/tiktok/callback', to: 'oauth#tiktok_callback'
      get 'oauth/youtube/login', to: 'oauth#youtube_login'
      get 'oauth/youtube/callback', to: 'oauth#youtube_callback'

      # User info routes
      get 'user_info', to: 'user_info#show'
      patch 'user_info', to: 'user_info#update'
      post 'user_info/watermark', to: 'user_info#update_watermark'
      get 'user_info/connected_accounts', to: 'user_info#connected_accounts'
      post 'user_info/disconnect_facebook', to: 'user_info#disconnect_facebook'
      post 'user_info/disconnect_twitter', to: 'user_info#disconnect_twitter'
      post 'user_info/disconnect_linkedin', to: 'user_info#disconnect_linkedin'
      post 'user_info/disconnect_google', to: 'user_info#disconnect_google'
      post 'user_info/disconnect_tiktok', to: 'user_info#disconnect_tiktok'
      post 'user_info/disconnect_youtube', to: 'user_info#disconnect_youtube'
      post 'user_info/toggle_instagram', to: 'user_info#toggle_instagram'
      get 'user_info/watermark_preview', to: 'user_info#watermark_preview'
      get 'user_info/standard_preview', to: 'user_info#standard_preview'

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
        end
        collection do
          post 'bulk_update', to: 'bucket_schedules#bulk_update'
          delete 'bulk_delete', to: 'bucket_schedules#bulk_delete'
          post 'rotation_create', to: 'bucket_schedules#rotation_create'
          post 'date_create', to: 'bucket_schedules#date_create'
        end
      end

      # Scheduler routes
      post 'scheduler/single_post', to: 'scheduler#single_post'
      post 'scheduler/schedule', to: 'scheduler#schedule'
      post 'scheduler/post_now/:id', to: 'scheduler#post_now'
      post 'scheduler/skip_image/:id', to: 'scheduler#skip_image'
      post 'scheduler/skip_image_single/:id', to: 'scheduler#skip_image_single'
      get 'scheduler/open_graph', to: 'scheduler#open_graph'

      # Sub-account management routes
      resources :sub_accounts, only: [:index, :create, :show, :update, :destroy] do
        collection do
          post 'switch/:id', to: 'sub_accounts#switch'
        end
      end
      
      # Account management routes
      get 'account/features', to: 'accounts#features'
      patch 'account/features', to: 'accounts#update_features'

      # Image management routes
      resources :images, only: [:create]

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

  # Defines the root path route ("/")
  root "health#show"
end
