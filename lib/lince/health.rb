require "json"
require "openssl"

module Lince
  # GET /lince/health: base de datos, caché y cola (Solid Queue), la versión desplegada y cifras de recursos.
  # 200 si todo va bien, 503 si no. Privado: sin el token del proyecto (Authorization: Bearer …) responde 404,
  # como si no existiera.
  class Health
    def initialize(app, path: Lince.config.health_path)
      @app, @path = app, path
    end

    def call(env)
      return @app.call(env) unless env["PATH_INFO"] == @path && %w[GET HEAD].include?(env["REQUEST_METHOD"])
      return [ 404, { "content-type" => "text/plain", "cache-control" => "no-store" }, [ "Not Found" ] ] unless authorized?(env)
      checks = { database: database, cache: cache, queue: queue }.compact
      ok = checks.values.all? { |v| v == "ok" }
      body = JSON.generate(status: ok ? "ok" : "degraded", version: Health.revision, lince: VERSION, checks: checks, metrics: Health.metrics)
      [ ok ? 200 : 503, { "content-type" => "application/json", "cache-control" => "no-store" }, [ body ] ]
    end

    # Cifras de recursos para Lince (sección Recursos). Lo que no se pueda medir en esta plataforma sale nil.
    def self.metrics
      { rss_mb: rss_mb, disk_free_pct: disk_free_pct, db_mb: db_mb }.merge(queue_metrics).compact
    rescue StandardError
      {}
    end

    def self.rss_mb
      File.read("/proc/self/status")[/VmRSS:\s+(\d+)/, 1]&.to_i&./(1024) if File.exist?("/proc/self/status")
    end

    # Disco libre donde vive la app (en Kamal, el volumen de storage si existe).
    def self.disk_free_pct
      path = defined?(Rails) && Rails.respond_to?(:root) && Rails.root ? (File.directory?(Rails.root.join("storage")) ? Rails.root.join("storage") : Rails.root).to_s : Dir.pwd
      line = IO.popen([ "df", "-Pk", path ], err: File::NULL, &:read).lines.last.to_s.split
      size, avail = line[1].to_i, line[3].to_i
      (100.0 * avail / size).round(1) if size.positive?
    end

    def self.db_mb
      return unless defined?(ActiveRecord::Base)
      config = ActiveRecord::Base.connection_db_config
      bytes = case config.adapter
      when /sqlite/ then Dir["#{config.database}*"].sum { File.size(it) }
      when /postg/ then ActiveRecord::Base.connection.select_value("SELECT pg_database_size(current_database())").to_i
      end
      (bytes / 1_048_576.0).round(1) if bytes
    end

    # Cola de Solid Queue: trabajos esperando, el más antiguo y los fallidos (en total y en la última hora).
    def self.queue_metrics
      return {} unless defined?(SolidQueue::ReadyExecution)
      oldest = SolidQueue::ReadyExecution.minimum(:created_at)
      { queue_ready: SolidQueue::ReadyExecution.count, queue_oldest_s: (oldest ? (Time.now - oldest).round : 0),
        failed_jobs: SolidQueue::FailedExecution.count, failed_jobs_1h: SolidQueue::FailedExecution.where(created_at: (Time.now - 3600)..).count }
    rescue StandardError
      {}
    end

    def self.revision
      ENV["KAMAL_VERSION"] || ENV["GIT_REVISION"] || (File.read("REVISION").strip if File.exist?("REVISION"))
    end

    private
      def authorized?(env)
        expected = Lince.config.token.to_s
        given = env["HTTP_AUTHORIZATION"].to_s.delete_prefix("Bearer ")
        !expected.empty? && given.bytesize == expected.bytesize && OpenSSL.fixed_length_secure_compare(given, expected)
      end

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

      # Hay al menos un proceso de Solid Queue vivo (latido en los últimos 5 minutos). Si la app nunca ha
      # arrancado ninguno (tiene la gema pero no la usa), no se comprueba.
      def queue
        return unless defined?(SolidQueue::Process)
        return unless SolidQueue::Process.exists?
        SolidQueue::Process.where(last_heartbeat_at: (Time.now - 300)..).exists? ? "ok" : "error"
      rescue StandardError
        "error"
      end
  end
end
