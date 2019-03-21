class Api::GithubWebhooksController < ActionController::Base
    skip_before_action :verify_authenticity_token
    include GithubWebhook::Processor
  
    # Handle push event
    def github_push(payload)
      if payload["repository"]["full_name"] == "HackGT/biodomes"
        NewPushJob.perform_later(payload)
      else
        puts "Ignoring push for #{payload["repository"]["full_name"]}."
      end
    end
    def github_check_suite(payload)
    end
    private
  
    def webhook_secret(payload)
      ENV['GITHUB_WEBHOOK_SECRET']
    end
  end
  