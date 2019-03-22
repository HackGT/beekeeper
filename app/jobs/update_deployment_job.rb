class UpdateDeploymentJob < ApplicationJob
  queue_as :default
  rescue_from(StandardError) do |exception|
      logger.error('Failed UpdateDeployment', exception)
      if @deployment_created
        @installation_client.create_deployment_status(@deployment["url"], 'failure')
        @installation_client.create_status(payload["repository"]["full_name"], payload["after"], 'failure')
      end
  end
  def perform(dome_name, app_name, config_path)
    logger.tagged(deployment: "#{app_name}-#{dome_name}") do
      FileUtils.rm_rf Rails.root.join('.output')
      FileUtils.mkdir Rails.root.join('.output')
      # Reload application data to load updated git reference
      app_config = YAML.safe_load(File.read(config_path))
      old_docker_tag = BeekeeperLoader::Beehive.dig(dome_name, 'apps', app_name, 'docker-tag')
      # Clear configuration
      BeekeeperLoader::Beehive[dome_name]['apps'][app_name] = {}
      # Load in new config
      BeehiveHelper.load_config(GLOBAL_CONFIG, app_config, config_path, BeekeeperLoader::Beehive)
      BeekeeperLoader::update_deployment_map(dome_name, app_name, BeekeeperLoader::Beehive[dome_name]['apps'][app_name]["git"]["slog"], BeekeeperLoader::Beehive[dome_name]['apps'][app_name]['config_path'])
      authenticate_app()
      authenticate_installation()
      # Only tell GitHub if we're on a new ref for this deployment so we don't spam deployments uncessarily
      if old_docker_tag != BeekeeperLoader::Beehive[dome_name]['apps'][app_name]['docker-tag']
        @deployment_created = true
        @deployment = @installation_client.create_deployment(BeekeeperLoader::Beehive[dome_name]['apps'][app_name]['git']['slog'], BeekeeperLoader::Beehive[dome_name]['apps'][app_name]['docker-tag'], { 
          :required_contexts => [], 
          :environment => "#{app_name}-#{dome_name}", 
          :auto_merge => false,
          :auto_inactive => true,
          :accept => "application/vnd.github.ant-man-preview+json",
          :transient_environment => true
        })
        @installation_client.create_deployment_status(@deployment['url'], 'in_progress',  {
          :context => "Beekeeper", 
          :accept => 'application/vnd.github.flash-preview+json',
        })
      else
        @deployment_created = false
        logger.debug('Not creating GitHub reference because deployment not updated')
      end
      
      # Write out the configuration update
      BeehiveHelper.gen_config(GLOBAL_CONFIG, dome_name, app_name, BeekeeperLoader::Beehive[dome_name]['apps'][app_name])
      # Write out the ingress (in cases that we are creating a new deployment)
      BeehiveHelper.write_ingress(BeekeeperLoader::Beehive)
      # Generate a new DNS entry (in cases that we are creating a new deployment)
      dns_entry = BeehiveHelper.gen_dns(GLOBAL_CONFIG, dome_name, app_name, BeekeeperLoader::Beehive[dome_name]['apps'][app_name])
      # Deploy Kubernetes objects. Kubernetes gracefully diffs any objects that have not been changed
      BeehiveHelper.deploy_kubernetes()
      # Deploy DNS. Gracefully handles cases where DNS entry already exists (in cases of version updates)
      BeehiveHelper.deploy_dns({ BeekeeperLoader::Beehive[dome_name]['apps'][app_name]['host'] => dns_entry })
      
      if @deployment_created
        @installation_client.create_deployment_status(@deployment['url'], 'success', {
          :environment_url => "https://#{BeekeeperLoader::Beehive[dome_name]['apps'][app_name]['host']}",
          :accept => 'application/vnd.github.ant-man-preview+json'
        })
      end
    end
  end
end
