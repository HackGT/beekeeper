class Api::VersionUpdatesController < ActionController::Base
    skip_before_action :verify_authenticity_token
    def create
        unless request.headers['Authorization'] == ENV['API_KEY']
            render json: {'message': 'Unauthorized', status: 403}, status: 403
            logger.info request.headers['Authorization']
            return
        end
        if params.has_key?('repo')
            apps = BeekeeperLoader::DeploymentMap[params['repo'].downcase]
            if apps.nil?
                render json: {'message': 'No deployments found', status: 200}, status: 200
            else
                apps.each do |app, app_data|
                    UpdateDeploymentJob.perform_later(app_data['domain'], app_data['app'], app_data['config_path'])
                end
                render json: {'message': "#{apps.length} deployments queued for update", status: 200}, status: 200
            end
        else
            render json: {'message': 'Please supply a repository name', status: 400}, status: 400
        end
    end
end
  