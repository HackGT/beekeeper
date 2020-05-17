class ErrorsController < ActionController::Base
    def not_found
        render json: {'message': 'Not found', status: 404}, status: 404
    end
end
  