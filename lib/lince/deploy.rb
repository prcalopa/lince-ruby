module Lince
  # Aviso de despliegue desde los hooks de Kamal, con lo que Kamal pone en el entorno.
  module Deploy
    EVENTS = %w[started finished failed].freeze

    module_function

    def notify(event, env = ENV, client: Lince.client)
      raise ArgumentError, "evento desconocido: #{event}" unless EVENTS.include?(event)
      version = env["KAMAL_VERSION"].to_s
      return false if version.empty?
      client.post("/ingest/v1/apps/deployments", payload(event, env))
    end

    def payload(event, env)
      { event: event, version: env["KAMAL_VERSION"], performer: env["KAMAL_PERFORMER"], destination: env["KAMAL_DESTINATION"],
        hosts: env["KAMAL_HOSTS"], runtime: env["KAMAL_RUNTIME"], lince: VERSION }.reject { |_, v| v.nil? || v.to_s.empty? }
    end
  end
end
