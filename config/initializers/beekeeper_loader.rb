require "beehive_helper"
BEEHIVE_URI = 'https://github.com/HackGT/beehive.git'.freeze
BEEHIVE_DIRECTORY_NAME = '.beehive'.freeze
GLOBAL_CONFIG = YAML.load_file(Rails.root.join('config/config.yml'))

require 'exception_notification/rails'

ExceptionNotification.configure do |config|
  config.ignored_exceptions += %w{'GithubWebhook::Processor::UnsupportedGithubEventError' NoMethodError} + ExceptionNotifier.ignored_exceptions
  config.add_notifier :slack, {
    webhook_url: ENV['SLACK_WEBHOOK'],
    backtrace_lines: 3
  }
end

module BeekeeperLoader
  DeploymentMap = Hash.new
  def BeekeeperLoader.update_deployment_map(dome_name, app_name, repo, config_path)
    repo = repo.downcase
    unless DeploymentMap.has_key?(repo)
      DeploymentMap[repo] = {}
    end
    DeploymentMap[repo]["#{dome_name}-#{app_name}"] = {
      'domain' => dome_name,
      'app' => app_name,
      'config_path' => config_path
    }
  end
  def BeekeeperLoader.remove_from_deployment_map(dome_name, app_name, repo)
    repo = repo.downcase
    if DeploymentMap.has_key?(repo)
      DeploymentMap[repo].delete("#{dome_name}-#{app_name}")
    end
  end
  Rails.logger.debug '[git] Starting load of Beehive'
  FileUtils.rm_rf BEEHIVE_DIRECTORY_NAME
  Repo = Git.clone(BEEHIVE_URI, BEEHIVE_DIRECTORY_NAME)
  # Disable renames for diffing
  Repo.config('diff.renames', 'false')

  Rails.logger.debug '[git] Clone complete'
  Beehive = BeehiveHelper.load_config_all(GLOBAL_CONFIG)
  Beehive.each do |dome_name, biodome|
    biodome['apps'].each do |app_name, app|
      update_deployment_map(dome_name, app_name, app["git"]["slog"], app['config_path'])
    end
  end
end