module Lince
  # El token sale, por orden, de LINCE_TOKEN, de las credenciales de Rails (lince.token) o de lo que se configure.
  class Configuration
    attr_accessor :endpoint, :token, :health_path, :timeout, :ignored_errors, :errors, :heartbeats, :requests

    def initialize
      @ignored_errors = []
      @errors = true      # captura de errores (solo en producción)
      @heartbeats = true  # latidos de config/recurring.yml (solo en producción)
      @requests = true    # tiempos y códigos de las peticiones (solo en producción)
      @endpoint = ENV.fetch("LINCE_ENDPOINT", "https://lince.perecalopa.dev")
      @token = ENV["LINCE_TOKEN"]
      @health_path = "/lince/health"
      @timeout = 5
    end

    def token
      @token ||= rails_credentials || Credentials.read(Dir.pwd)
    end

    # Dentro de la app ya están cargadas; desde los hooks de Kamal, no.
    def rails_credentials
      Rails.application.credentials.dig(:lince, :token) if defined?(Rails) && Rails.respond_to?(:application) && Rails.application
    rescue StandardError
      nil
    end
  end

  # Lee lince.token de las credenciales cifradas sin arrancar Rails (los hooks de Kamal corren en el portátil).
  module Credentials
    module_function

    def read(root)
      require "active_support"
      require "active_support/encrypted_configuration"
      candidates(root).each do |file, key|
        next unless File.exist?(file) && (File.exist?(key) || ENV["RAILS_MASTER_KEY"])
        config = ActiveSupport::EncryptedConfiguration.new(config_path: file, key_path: key, env_key: "RAILS_MASTER_KEY", raise_if_missing_key: false)
        token = config.config.dig(:lince, :token)
        return token if token
      rescue StandardError
        next
      end
      nil
    rescue LoadError
      nil
    end

    def candidates(root)
      [ [ "#{root}/config/credentials/production.yml.enc", "#{root}/config/credentials/production.key" ],
        [ "#{root}/config/credentials.yml.enc", "#{root}/config/master.key" ] ]
    end
  end
end
