# encoding: utf-8
require "logstash/plugin_mixins/aws_config/generic"

module LogStash::PluginMixins::AwsConfig::V2
  def self.included(base)
    base.extend(self)
    base.send(:include, LogStash::PluginMixins::AwsConfig::Generic)
  end

  public
  def aws_options_hash
    opts = {}

    opts[:http_proxy] = @proxy_uri if @proxy_uri

    if self.respond_to?(:aws_service_endpoint)
      # used by CloudWatch to basically do the same as bellow (returns { region: region })
      opts.merge!(self.aws_service_endpoint(@region))
    else
      # NOTE: setting :region works with the aws sdk (resolves correct endpoint)
      opts[:region] = @region
    end

    opts[:endpoint] = @endpoint unless @endpoint.nil?

    if @access_key_id.is_a?(NilClass) ^ @secret_access_key.is_a?(NilClass)
      @logger.warn("Likely config error: Only one of access_key_id or secret_access_key was provided but not both.")
    end

    if @role_arn
      credentials = assume_role(opts)
      opts = { :credentials => credentials }
    else
      credentials = aws_credentials
      opts[:credentials] = credentials if credentials
    end

    return opts
  end

  private

  def aws_credentials
    if @access_key_id && @secret_access_key
      credentials_opts = {
        :access_key_id => @access_key_id,
        :secret_access_key => @secret_access_key.value
      }

      credentials_opts[:session_token] = @session_token.value if @session_token
      Aws::Credentials.new(credentials_opts[:access_key_id],
                           credentials_opts[:secret_access_key],
                           credentials_opts[:session_token])
    elsif @aws_credentials_file
      credentials_opts = YAML.load_file(@aws_credentials_file)
      credentials_opts.default_proc = lambda { |hash, key| hash.fetch(key.to_s, nil) }
      Aws::Credentials.new(credentials_opts[:access_key_id],
                           credentials_opts[:secret_access_key],
                           credentials_opts[:session_token])
    else
      nil # AWS client will read ENV or ~/.aws/credentials
    end
  end
  alias credentials aws_credentials

  def assume_role(opts = {})
    unless opts.key?(:credentials)
      credentials = aws_credentials
      opts[:credentials] = credentials if credentials
    end

    Aws::AssumeRoleCredentials.new(
        :client => Aws::STS::Client.new(opts),
        :role_arn => @role_arn,
        :role_session_name => @role_session_name
    )
  end
end
