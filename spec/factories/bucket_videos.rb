FactoryBot.define do
  factory :bucket_video do
    bucket
    video
    friendly_name { Faker::Lorem.word.titleize }
    description { Faker::Lorem.paragraph }
    twitter_description { Faker::Lorem.sentence(word_count: 10) }
    post_to { 0 }
    use_watermark { true }
  end
end

