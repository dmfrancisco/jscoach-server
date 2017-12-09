require "twitter"

namespace :app do
  def twitter
    client = Twitter::REST::Client.new do |config|
      config.consumer_key        = Rails.application.secrets.twitter_consumer_key
      config.consumer_secret     = Rails.application.secrets.twitter_consumer_secret
      config.access_token        = Rails.application.secrets.twitter_access_token
      config.access_token_secret = Rails.application.secrets.twitter_access_token_secret
    end
  end

  desc "Tweet about a package"
  task :tweet => :environment do
    # Only run every two hours (the heroku scheduler only supports hourly)
    return if Time.current.hour.odd?

    begin
      package = Package.tweetable.first

      if package.present?
        tweet = package.decorate.to_tweet

        package.tweeted = true
        package.save!

        twitter.update(tweet) unless tweet.nil?
      end
    rescue => e
      JsCoach.error e.to_s
      ExceptionNotifier.notify_exception(e) # Send backtrace
    end
  end
end
