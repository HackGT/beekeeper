class NewPushJob < ApplicationJob
    queue_as :default
    rescue_from(StandardError) do |exception|
        logger.error('Failed NewPush', exception)
        @installation_client.create_deployment_status(@deployment["url"], 'failure')
        @installation_client.create_status(payload["repository"]["full_name"], payload["after"], 'failure')
        ExceptionNotifier.notify_exception(exception)
    end
    before_perform do |job|
        authenticate_app()
        payload = job.arguments.first
        @deployment = @installation_client.create_deployment(payload["repository"]["full_name"], payload["after"], { :required_contexts => [] })
        @installation_client.create_deployment_status(@deployment["url"], 'in_progress', {
            :context => "Beekeeper", 
            :description => "Beekeeper deploy succeeded", 
            :accept => "application/vnd.github.flash-preview+json"
        })
    end
    after_perform do |job|
        authenticate_app()
        payload = job.arguments.first
        @installation_client.create_deployment_status(@deployment["url"], 'success')
        @installation_client.create_status(payload["repository"]["full_name"], payload["after"], 'success')
    end
    def perform(payload)
        logger.debug "Got new head #{payload['after']}"
        if payload['ref'] == 'refs/heads/master'
            g = BeekeeperLoader::Repo
            current_head = g.revparse('HEAD')
            if current_head != payload['before']
                raise 'Pushes are not syncronized with shadow repository'    
            end
            g.pull
            diff = g.diff(payload['before'], payload['after'])
            diff.each do |file|
                file_path = Rails.root.join(BEEHIVE_DIRECTORY_NAME, file.path).to_s
                dome_name, app_name = BeehiveHelper.parse_path(file_path)
                if file.type == 'deleted'
                    logger.debug("#{file_path} deleted")
                    DeleteDeploymentJob.perform_now(dome_name, app_name, file_path)
                else
                    logger.debug("#{file_path} created/modified")
                    UpdateDeploymentJob.perform_now(dome_name, app_name, file_path)
                end
            end
        else
            logger.debug "Not deploying for non-master ref #{payload['ref']}"
        end
    end
end