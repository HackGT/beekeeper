module BeehiveHelper
  require 'yaml'
  require 'json'
  require 'erb'
  require 'fileutils'
  require 'open-uri'
  require 'securerandom'
  require 'filemagic'
  require 'base64'
  require 'git'
  require 'English'
  require 'kubeclient'
  require 'cloudflare'
  require 'base64'
  require 'yaml'


  SECRETS_URL = 'http://localhost:8001/api/v1/namespaces/kube-system'\
                '/services/kubernetes-dashboard/proxy/#!/secret'.freeze
  SOURCE_DIR = Rails.root.join('.beehive/')
  KUBE_GLOB = Rails.root.join('.output/*.yaml')
  KUBE_OUT_DIR = Rails.root.join('.output/')

  TEMPLATES_DIR = Rails.root.join('templates/')
  CONFIG_ROOT_LEN = SOURCE_DIR.to_s.split(File::SEPARATOR).length
  YAML_GLOB = ['*.yaml', '*.yml'].map { |f| File.join SOURCE_DIR, '**', f }

  SERVICE_TEMPLATE = File.join TEMPLATES_DIR, 'service.yaml.erb'
  DEPLOYMENT_TEMPLATE = File.join TEMPLATES_DIR, 'deployment.yaml.erb'
  INGRESS_TEMPLATE = File.join TEMPLATES_DIR, 'ingress.yaml.erb'
  CERTIFICATE_TEMPLATE = File.join TEMPLATES_DIR, 'certificate.yaml.erb'
  SECRETS_TEMPLATE = File.join TEMPLATES_DIR, 'secrets.yaml.erb'
  SECRET_FILES_TEMPLATE = File.join TEMPLATES_DIR, 'secret-files.yaml.erb'
  CONFIG_MAP_TEMPLATE = File.join TEMPLATES_DIR, 'configmap.yaml.erb'
  FALLBACK_SECRETS_TEMPLATE = File.join TEMPLATES_DIR, 'fallback-secrets.yaml.erb'


  POD_FILE_DIR = '/etc/files/'
  INVALID_YAML_KEY = /[^-._a-zA-Z0-9]+/
  INVALID_HOSTNAME = /[^a-zA-Z0-9-]+/
  GITHUB_PRIVATE_KEY = OpenSSL::PKey::RSA.new(ENV['GITHUB_PRIVATE_KEY'].gsub('\n', "\n"))
  GITHUB_APP_IDENTIFIER = ENV['GITHUB_APP_IDENTIFIER']

  def BeehiveHelper.authenticate_app()
      # Refresh install token every 10 minutes
      if !defined?(@last_use) || @last_use + (10*60) < Time.now.to_i
        puts '[beekeeper] Renewing GitHub token'
        @new_expiry = Time.now.to_i + (9 * 60)
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
        @installation_id = ENV['GITHUB_INSTALLATION_ID']
        @installation_token = @app_client.create_app_installation_access_token(@installation_id, accept: Octokit::Preview::PREVIEW_TYPES[:integrations])[:token]
        @installation_client = Octokit::Client.new(bearer_token: @installation_token, accept:[])
        @last_use = Time.now.to_i
      end
  end


  class IncorrectFileConfigurationError < StandardError; end

  def BeehiveHelper.text?(text)
    fm = FileMagic.new(FileMagic::MAGIC_MIME)
    fm.buffer(text) =~ %r{^text/}
  ensure
    fm.close
  end

  def BeehiveHelper.basename_no_ext(file)
    File.basename(file, File.extname(file))
  end

  def BeehiveHelper.make_shortname(config_name, app_name)
    (
      if config_name && app_name == 'main'
        config_name
      else
        app_name
      end
    ).downcase
  end

  def BeehiveHelper.make_host(global_config, app_name, dome_name)
    if app_name == 'main'
      global_config['domain']['host']
    elsif dome_name == 'default'
      "#{app_name}.#{global_config['domain']['host']}"
    else
      "#{app_name}.#{dome_name}.#{global_config['domain']['host']}"
    end
  end

  def BeehiveHelper.make_dockertag(remote, branch: 'master', rev: nil)
    # refs/heads/ gives an exact match, just using the branch name can
    # return results like:
    # <hash>	refs/heads/changeset-release/master
    # <hash>	refs/heads/master
    return rev unless rev.nil?
    `git ls-remote '#{remote}' 'refs/heads/#{branch}'`
      .lines[0]
      .split[0]
  end

  def BeehiveHelper.github_file(file, slog, branch: 'master', rev: nil)
    BeehiveHelper.authenticate_app()
    Base64.decode64(@installation_client.contents(slog, :path => file, :ref => rev || branch).content)
  end

  def BeehiveHelper.safe_github_file(file, slog)
    github_file(file, slog)
  rescue
    nil
  end

  def BeehiveHelper.fetch_deployment(slog, branch: 'master', rev: nil)
    text = github_file('deployment.yaml', slog, branch: branch, rev: rev)
    YAML.safe_load(text)
  end

  def BeehiveHelper.make_file_opts(opts)
    if opts.is_a?(Hash) && opts.include?('path') && opts['path'].is_a?(String)
      raise "Should be string: #{opts['env']}." unless opts['env'].is_a?(String)
      {
        path: opts['path'],
        env: opts['env']
      }
    elsif opts.is_a?(String)
      {
        path: opts['path']
      }
    else
      raise "Could not find path for file #{mount_root}/#{name}"
    end
  end

  def BeehiveHelper.safe_yaml_key(string)
    string.gsub(INVALID_YAML_KEY, '--')
  end

  def BeehiveHelper.make_file_config(file_opts, target, mount_root, slog, config_path)
    root = if file_opts[:path][0] == '/'
          SOURCE_DIR
          else
            File.dirname config_path
          end

    local_path = File.join root, file_opts[:path]
    contents = if File.file?(local_path)
                File.read(local_path)
              else
                safe_github_file(file_opts[:path], slog)
              end
    if contents.nil?
      raise "File not found in Beehive or on GH with path: #{file_opts[:path]}."
    end

    contents = Base64.encode64(contents) unless text?(contents)

    {
      contents: contents,
      env: file_opts[:env],
      path: target,
      key: safe_yaml_key(target),
      full_path: File.join(mount_root, target)
    }
  end

  def BeehiveHelper.verify_mount_root(mount_root)
    if mount_root == 'anywhere'
      mount_root = POD_FILE_DIR
    elsif mount_root[0] != '/'
      raise "Mount root must specify absolute path: #{mount_root}."
    end
    mount_root
  end

  def BeehiveHelper.parse_file_info(app_config, uid, slog, config_path)
    return {} if app_config['files'].nil?
    raise '`files` key must be a Hash.' unless app_config['files'].is_a? Hash
    app_config['files'].each_with_object({}) \
    do |(mount_root, mount_config), files|
      mount_config = mount_config.with_indifferent_access
      contents = {}
      root = verify_mount_root(mount_root)

      if mount_config['secret']
        contents = mount_config['contents'].each_with_object({}) \
        do |(name, opts), files_config|

          files_config[name] = {}
          next unless opts.is_a? Hash

          files_config[name] = {
            env: opts['env'],
            path: name,
            full_path: File.join(root, name)
          }
        end
      else
        contents = mount_config['contents'].each_with_object({}) \
        do |(name, opts), files_config|
          files_config[name] = make_file_config(make_file_opts(opts),
                                                name,
                                                root,
                                                slog,
                                                config_path)
        end
      end

      files[root] = {
        contents: contents,
        secret: mount_config['secret'],
        key: uid + '--' + safe_yaml_key(root.gsub(%r{(^/+|/+$)}, ''))
      }
      files
    end
  end

  def BeehiveHelper.load_app_data(global_config, data, app_config, dome_name, app_name, path)
    # generate more configs part
    if app_config['git'].is_a? String
      remote = app_config['git']
      app_config['git'] = {}
      app_config['git']['remote'] = remote
    end
    git = app_config['git']['remote']
    branch = app_config['git']['branch'] || 'master'
    git_rev = app_config['git']['rev']
    git_rev = git_rev.downcase unless git_rev.nil?

    git_parts = git.split(File::SEPARATOR)
    repo_name = basename_no_ext(git_parts[-1])
    org_name = git_parts[-2]
    slog = "#{org_name}/#{repo_name}"

    shortname = make_shortname app_config['name'], app_name

    uid = "#{shortname}-#{dome_name}"
    if /\d/.match(uid[0])
      suid = "s#{uid}"
    else
      suid = nil
    end
    base_config = fetch_deployment(slog, branch: branch, rev: git_rev)
    app_config = base_config.deep_merge(app_config)
    docker_tag = make_dockertag git, branch: branch, rev: git_rev

    host = make_host global_config, app_name, dome_name

    files = parse_file_info(app_config, uid, slog, path)

    data[dome_name] = {} unless data.key? dome_name
    data[dome_name]['name'] = dome_name
    data[dome_name]['apps'] = {} unless data[dome_name].key? 'apps'
    data[dome_name]['apps'][app_name] = app_config
    data[dome_name]['apps'][app_name]['config_path'] = path
    data[dome_name]['apps'][app_name]['git']['slog'] = slog.downcase
    data[dome_name]['apps'][app_name]['git']['user'] = org_name.downcase
    data[dome_name]['apps'][app_name]['git']['shortname'] = repo_name.downcase
    data[dome_name]['apps'][app_name]['git']['rev'] = git_rev
    data[dome_name]['apps'][app_name]['shortname'] = shortname
    data[dome_name]['apps'][app_name]['docker-tag'] = docker_tag
    data[dome_name]['apps'][app_name]['default_image_name'] = "#{org_name.downcase}/#{repo_name.downcase}:#{docker_tag}"
    if (data[dome_name]['apps'][app_name].has_key?("image_name"))
      data[dome_name]['apps'][app_name]['image_name'] = "#{data[dome_name]['apps'][app_name]['image_name']}:#{docker_tag}"
    end
    data[dome_name]['apps'][app_name]['uid'] = uid
    data[dome_name]['apps'][app_name]['suid'] = suid
    data[dome_name]['apps'][app_name]['host'] = host.downcase
    data[dome_name]['apps'][app_name]['files'] = files
    data
  end
  def BeehiveHelper.parse_path(path)
    components = path.split(File::SEPARATOR).drop(CONFIG_ROOT_LEN)
    dome_name, app_name = components

    if dome_name =~ /main\.ya*ml/ && app_name.nil?
      dome_name = 'default'
      app_name = 'main'
    elsif components.length > 2
      raise "YAML configs cannot go more than 1 directory deep! #{file}"
    elsif app_name.nil?
      app_name = basename_no_ext dome_name
      dome_name = 'default'
    else
      app_name = basename_no_ext app_name
    end

    raise "Dome name #{dome_name} invalid because it cannot be a domain name." \
      if INVALID_HOSTNAME.match?(dome_name)

    raise "App name #{app_name} invalid because it cannot be a domain name." \
      if INVALID_HOSTNAME.match?(app_name)
    return dome_name, app_name 
  end
  def BeehiveHelper.load_config(global_config, app_config, file, data)
    Rails.logger.debug "[beekeeper] Parsing #{file}."
    dome_name, app_name = parse_path(file)

    load_app_data(global_config, 
                  data,
                  app_config,
                  dome_name.downcase,
                  app_name.downcase,
                  file)
  end
  # Load all the configuration files!
  def BeehiveHelper.load_config_all(global_config)
    # Go through all the .yaml and .yml files here!
    Dir[*YAML_GLOB]
      .select { |f| File.file? f }
      .reject { |f| basename_no_ext(f)[0] == '.' || f[0] == '.' }
      .map    { |f| [YAML.safe_load(File.read(f)), f] }
      .reject { |y| y[0]['ignore'] }
      .each_with_object({}) do |(app_config, file), data|
      begin
        load_config(global_config, app_config, file, data)
      rescue => e
        ExceptionNotifier.notify_exception(e, data: {message: "Could not load file #{file} on start, please check that it is valid"})
        puts e
      end
    end
  end

  def BeehiveHelper.write_config(path, template, bind)
    raise "File #{path} already exists! Not overwriting!" if File.exist? path
    File.open path, 'w' do |file|
      # generate the config
      data = ERB.new(File.read(template)).result(bind)
      file.write(data)
    end
  end

  def BeehiveHelper.gen_config(global_config, dome_name, app_name, app)
    app['mongo'] = global_config['mongo']['host']
    app['postgres'] = global_config['postgres']

    app['files'].each do |mount, volume|
      files = volume[:contents]

      if volume[:secret]
        path = File.join KUBE_OUT_DIR, "#{volume[:key]}-secret-files.yaml"
        Rails.logger.debug "[beekeeper] Writing #{path}."
        write_config(path, SECRET_FILES_TEMPLATE, binding)
      else
        path = File.join KUBE_OUT_DIR, "#{volume[:key]}-configmap.yaml"
        Rails.logger.debug "[beekeeper] Writing #{path}."
        write_config(path, CONFIG_MAP_TEMPLATE, binding)
      end
    end

    path = File.join KUBE_OUT_DIR, "#{app_name}-#{dome_name}-deployment.yaml"
    Rails.logger.debug "[beekeeper] Writing #{path}."
    write_config(path, DEPLOYMENT_TEMPLATE, binding)

    path = File.join KUBE_OUT_DIR, "#{app_name}-#{dome_name}-service.yaml"
    Rails.logger.debug "[beekeeper] Writing #{path}."
    write_config(path, SERVICE_TEMPLATE, binding)

    unless app['secrets'].nil?
      path = File.join KUBE_OUT_DIR, "#{app_name}-#{dome_name}-secrets.yaml"
      Rails.logger.debug "[beekeeper] Writing #{path}."
      write_config(path, SECRETS_TEMPLATE, binding)
      path = File.join KUBE_OUT_DIR, "git-#{app['git']['slog'].tr '/', '-'}" \
                                    '-secrets.yaml'
    end
    unless File.exist? path
      Rails.logger.debug "[beekeeper] Writing #{path}."
      write_config(path, FALLBACK_SECRETS_TEMPLATE, binding)
    end
  end
  def BeehiveHelper.write_ingress(beehive)
    path = File.join KUBE_OUT_DIR, 'ingress.yaml'
    Rails.logger.debug "[beekeeper] Writing #{path}."
    write_config(path, INGRESS_TEMPLATE, binding)
    path = File.join KUBE_OUT_DIR, 'certificates.yaml'
    Rails.logger.debug "[beekeeper] Writing #{path}."
    write_config(path, CERTIFICATE_TEMPLATE, binding)
  end

  def BeehiveHelper.gen_dns(global_config, dome_name, app_name, app)
    entry = {
      'type' => 'A',
      'content' => global_config['cluster']['host'],
      'proxied' => dome_name == 'default'
    }
    entry
  end
  
  def BeehiveHelper.deploy_dns(targets)
    Cloudflare.connect(key: ENV['CLOUDFLARE_AUTH'], email: ENV['CLOUDFLARE_EMAIL']) do |connection|
      zone = connection.zones.find_by_id(ENV['CLOUDFLARE_ZONE'])
      # add the remaining records
      targets.each do |name, record|
        Rails.logger.debug "[beekeeper] Creating Cloudflare DNS: #{record.to_json}"
        record['name'] = name
        begin
          zone.dns_records.create(record["type"], record["name"], record["content"], proxied: record["proxied"])
        rescue
          Rails.logger.debug "[beekeeper] #{record["name"]} already created"
        end
      end
    end
  end
  
  def BeehiveHelper.deploy_kubernetes
    Dir[KUBE_GLOB]
      .map { |f| [YAML.safe_load(File.read(f)), f] }
      .each do |(config, path)|
  
      # create based on the kind of file
      Rails.logger.debug "[beekeeper] Deploying #{path}."
  
      # We don't want to overwrite over secrets since they are stateful.
      if config['kind'].casecmp('secret').zero?
        `kubectl --namespace=default describe secret '#{config['metadata']['name']}' &>/dev/null`
        puts `kubectl --namespace=default apply -f '#{path}'` unless $CHILD_STATUS.success?
      else
        puts `kubectl --namespace=default apply -f '#{path}'`
      end
  
      raise 'kubectl exited with non-zero status.' unless $CHILD_STATUS.success?
    end
  end
  
  def BeehiveHelper.delete_kubernetes(name)
    Rails.logger.debug "[beekeeper] Deleting deployment #{name}."
    Rails.logger.debug `kubectl --namespace=default delete deployment #{name}`
    Rails.logger.debug "[beekeeper] Deleting service #{name}."
    Rails.logger.debug `kubectl --namespace=default delete service #{name}`
  end
  def BeehiveHelper.delete_dns(host)
    Cloudflare.connect(key: ENV['CLOUDFLARE_AUTH'], email: ENV['CLOUDFLARE_EMAIL']) do |connection|
      zone = connection.zones.find_by_id(ENV['CLOUDFLARE_ZONE'])
      zone.dns_records.find_by_name(host).delete
    end
  end
end
