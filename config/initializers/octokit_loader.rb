GITHUB_PRIVATE_KEY = OpenSSL::PKey::RSA.new(ENV['GITHUB_PRIVATE_KEY'].gsub('\n', "\n"))
GITHUB_APP_IDENTIFIER = ENV['GITHUB_APP_IDENTIFIER']
def authenticate_app
    payload = {
        # The time that this JWT was issued, _i.e._ now.
        iat: Time.now.to_i,

        # JWT expiration time (10 minute maximum)
        exp: Time.now.to_i + (10 * 60),

        # Your GitHub App's identifier number
        iss: GITHUB_APP_IDENTIFIER
    }

    # Cryptographically sign the JWT.
    jwt = JWT.encode(payload, GITHUB_PRIVATE_KEY, 'RS256')

    # Create the Octokit client, using the JWT as the auth token.
    @app_client ||= Octokit::Client.new(bearer_token: jwt)
  end

# Instantiate an Octokit client, authenticated as an installation of a
# GitHub App, to run API operations.
def authenticate_installation()
    @installation_id = ENV['GITHUB_INSTALLATION_ID']
    @installation_token = @app_client.create_app_installation_access_token(@installation_id)[:token]
    @installation_client = Octokit::Client.new(bearer_token: @installation_token, accept:[])
end
