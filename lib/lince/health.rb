require "json"

module Lince
  # GET /lince/health: base de datos, caché y cola (Solid Queue) con la versión desplegada. 200 si todo va bien, 503 si no.
  # No da datos sensibles: solo nombres de comprobación, ok o error y versiones.
  class Health
    def initialize(app, path: Lince.config.health_path)
      @app, @path = app, path
    end

    def call(env)
      return @app.call(env) unless env["PATH_INFO"] == @path && %w[GET HEAD].include?(env["REQUEST_METHOD"])
      checks = { database: database, cache: cache, queue: queue }.compact
      ok = checks.values.all? { |v| v == "ok" }
      body = JSON.generate(status: ok ? "ok" : "degraded", version: Health.revision, lince: VERSION, checks: checks)
      [ ok ? 200 : 503, { "content-type" => "application/json", "cache-control" => "no-store" }, [ body ] ]
    end

    def self.revision
      ENV["KAMAL_VERSION"] || ENV["GIT_REVISION"] || (File.read("REVISION").strip if File.exist?("REVISION"))
    end

    private
      def database
        return unless defined?(ActiveRecord::Base)
        ActiveRecord::Base.connection.select_value("SELECT 1")
        "ok"
      rescue StandardError
        "error"
      end

      def cache
        return unless defined?(Rails) && Rails.respond_to?(:cache) && Rails.cache
        key = "lince:health:#{Process.pid}"
        Rails.cache.write(key, "1", expires_in: 60) && Rails.cache.read(key) == "1" ? "ok" : "error"
      rescue StandardError
        "error"
      end

      # Hay al menos un proceso de Solid Queue vivo (latido en los últimos 5 minutos).
      def queue
        return unless defined?(SolidQueue::Process)
        SolidQueue::Process.where(last_heartbeat_at: (Time.now - 300)..).exists? ? "ok" : "error"
      rescue StandardError
        "error"
      end
  end
end
