require "lince/version"
require "lince/configuration"
require "lince/client"
require "lince/health"
require "lince/deploy"
require "lince/installer"
require "lince/railtie" if defined?(Rails::Railtie)

# Cliente de Lince para apps Rails: /lince/health y avisos de despliegue desde los hooks de Kamal.
module Lince
  class << self
    def config = @config ||= Configuration.new
    def configure = yield(config)
    def client = Client.new(config)
  end
end
