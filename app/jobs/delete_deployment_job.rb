class DeleteDeploymentJob < ApplicationJob
  queue_as :default
  rescue_from(StandardError) do |exception|
    logger.error('Failed DeleteDeployment', exception)
    ExceptionNotifier.notify_exception(exception, data: {dome_name: arguments[0], app_name: arguments[1]})
  end
  def perform(dome_name, app_name, config_path)
    logger.tagged(deployment: "#{app_name}-#{dome_name}") do
      authenticate_app()
      @deployment = @installation_client.create_deployment(BeekeeperLoader::Beehive[dome_name]['apps'][app_name]['git']['slog'],  BeekeeperLoader::Beehive[dome_name]['apps'][app_name]['docker-tag'], { 
        :required_contexts => [], 
        :environment => "#{app_name}-#{dome_name}", 
        :auto_merge => false,
        :auto_inactive => true,
        :accept => "application/vnd.github.ant-man-preview+json"
      })
      @installation_client.create_deployment_status(@deployment['url'], 'success',  {
        :auto_inactive => true,
        :accept => 'application/vnd.github.ant-man-preview+json'
      })
      @installation_client.create_deployment_status(@deployment['url'], 'inactive',  {
        :context => "Beekeeper", 
        :accept => 'application/vnd.github.ant-man-preview+json'
      })
      
      begin
        app = BeekeeperLoader::Beehive[dome_name]['apps'][app_name]
      rescue
        raise "Could not find #{app_name}-#{dome_name}"
      end
      name = "#{app_name}-#{dome_name}"
      BeehiveHelper.delete_kubernetes(name)
      BeehiveHelper.delete_dns(app["host"])
      BeekeeperLoader::remove_from_deployment_map(dome_name, app_name, app["git"]["slog"])
      BeekeeperLoader::Beehive[dome_name]['apps'].delete(app_name)
    end
  end
end
