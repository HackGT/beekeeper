require_relative 'boot'

require "rails"

# Pick the frameworks you want:
# require "active_model/railtie"
require "active_job/railtie"
# require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_view/railtie"
# require "action_cable/engine"
# require "sprockets/railtie"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module MyApi
  class Application < Rails::Application
    config.autoload_paths << Rails.root.join('lib')
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 5.2

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # Set concurrency to 1 explicitly
    config.active_job.queue_adapter = ActiveJob::QueueAdapters::AsyncAdapter.new(max_threads: 1)
    
    # Use the lowest log level to ensure availability of diagnostic information
    # when problems arise.
    config.log_level = :debug

    if ENV["RAILS_LOG_TO_STDOUT"].present?
      STDOUT.sync = true
      config.rails_semantic_logger.add_file_appender = false
      config.semantic_logger.add_appender(io: STDOUT, level: config.log_level, formatter: config.rails_semantic_logger.format)
    end
  end
end
