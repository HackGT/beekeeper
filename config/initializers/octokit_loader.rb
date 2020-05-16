GITHUB_PRIVATE_KEY = OpenSSL::PKey::RSA.new(ENV['GITHUB_PRIVATE_KEY'].gsub('\n', "\n"))
GITHUB_APP_IDENTIFIER = ENV['GITHUB_APP_IDENTIFIER']
GITHUB_INSTALLATION_ID = ENV['GITHUB_INSTALLATION_ID']
stack = Faraday::RackBuilder.new do |builder|
    builder.use Faraday::Request::Retry, exceptions: [Octokit::ServerError, Octokit::Unauthorized]
end
def authenticate_app()
    # Refresh token within 10 minutes of expiry
    if !defined?(@expiry) || @expiry.to_i < Time.now.to_i + + 10*60
        payload = {
            # The time that this JWT was issued, _i.e._ now.
            iat: Time.now.to_i,
            # JWT expiration time (10 minute maximum)
            exp: Time.now.to_i + (9 * 60),
            # Your GitHub App's identifier number
            iss: GITHUB_APP_IDENTIFIER
        }

        # Cryptographically sign the JWT.
        jwt = JWT.encode(payload, GITHUB_PRIVATE_KEY, 'RS256')

        # Create the Octokit client, using the JWT as the auth token.
        @app_client = Octokit::Client.new(bearer_token: jwt)
        resp = @app_client.create_app_installation_access_token(GITHUB_INSTALLATION_ID, accept: Octokit::Preview::PREVIEW_TYPES[:integrations])
        @installation_client = Octokit::Client.new(bearer_token: resp.token)
        @expiry = resp.expires_at
        puts '[beekeeper] Renewed GitHub token with expiry %i' % [@expiry]
    end
end