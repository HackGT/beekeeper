class ErrorsController < ActionController::Base
    def not_found
        render json: {'message': 'not found', status: 404}, status: 404
    end
end
  