require "lince/version"
require "lince/configuration"
require "lince/client"
require "lince/health"
require "lince/deploy"
require "lince/scrubber"
require "lince/errors"
require "lince/heartbeats"
require "lince/requests"
require "lince/installer"
require "lince/railtie" if defined?(Rails::Railtie)

# Cliente de Lince para apps Rails: /lince/health, avisos de despliegue desde los hooks de Kamal, errores de
# producción y latidos de los trabajos recurrentes.
module Lince
  class << self
    def config = @config ||= Configuration.new
    def configure = yield(config)
    def client = Client.new(config)
  end
end
