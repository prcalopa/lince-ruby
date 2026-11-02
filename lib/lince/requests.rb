module Lince
  # Métricas de peticiones por minuto: cuántas, cuántas 4xx y 5xx, y un histograma de tiempos (total y por ruta
  # Controlador#acción). Se mandan cada minuto desde un hilo aparte. No se guarda nada de la petición: ni ruta con
  # ids, ni parámetros, ni cabeceras.
  class Requests
    BUCKETS = [ 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10_000 ].freeze # ms; el último hueco es «más»
    SKIP = %r{\A/(up|lince/health|assets/|cable|favicon|robots\.txt|service-worker|manifest)}
    MAX_ROUTES = 25

    def self.bucket(ms) = BUCKETS.index { ms <= it } || BUCKETS.size

    def initialize(app, collector: Lince::Requests.collector)
      @app, @collector = app, collector
    end

    def call(env)
      return @app.call(env) if env["PATH_INFO"].to_s.match?(SKIP)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      status = 500
      begin
        status, headers, body = @app.call(env)
        [ status, headers, body ]
      ensure
        ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
        @collector.record(route(env), status.to_i, ms)
      end
    end

    def self.collector = @collector ||= Collector.new

    private
      def route(env)
        c = env["action_controller.instance"]
        c.respond_to?(:action_name) ? "#{c.class.name}##{c.action_name}" : nil
      rescue StandardError
        nil
      end

    class Collector
      def initialize(client: nil, interval: 60, clock: -> { Time.now.utc })
        @client, @interval, @clock, @minutes, @mutex = client, interval, clock, {}, Mutex.new
      end

      def record(route, status, ms)
        minute = @clock.call.strftime("%Y-%m-%dT%H:%M:00Z")
        b = Requests.bucket(ms)
        @mutex.synchronize do
          m = @minutes[minute] ||= { total: 0, s4xx: 0, s5xx: 0, hist: Array.new(BUCKETS.size + 1, 0), routes: {} }
          m[:total] += 1
          m[:s4xx] += 1 if status.between?(400, 499)
          m[:s5xx] += 1 if status >= 500
          m[:hist][b] += 1
          if route && (m[:routes].key?(route) || m[:routes].size < 200)
            r = m[:routes][route] ||= { count: 0, ms: 0, s5xx: 0, hist: Array.new(BUCKETS.size + 1, 0) }
            r[:count] += 1
            r[:ms] += ms
            r[:s5xx] += 1 if status >= 500
            r[:hist][b] += 1
          end
        end
        ensure_thread
      rescue StandardError
        nil
      end

      # Manda los minutos ya cerrados (el actual sigue abierto).
      def flush(all: false)
        current = @clock.call.strftime("%Y-%m-%dT%H:%M:00Z")
        batch = @mutex.synchronize do
          done = @minutes.keys.select { all || it < current }
          done.map { |k| [ k, @minutes.delete(k) ] }
        end
        return if batch.empty?
        minutes = batch.map do |minute, m|
          routes = m[:routes].sort_by { -_2[:ms] }.first(MAX_ROUTES).map { |name, r| r.merge(route: name) }
          { minute: minute, total: m[:total], s4xx: m[:s4xx], s5xx: m[:s5xx], hist: m[:hist], routes: routes }
        end
        (@client || Lince.client).post("/ingest/v1/apps/requests", { buckets: BUCKETS, minutes: minutes })
      end

      private
        def ensure_thread
          return if @thread&.alive? && @pid == Process.pid
          @pid = Process.pid
          @thread = Thread.new do
            loop do
              sleep @interval
              flush
            rescue StandardError
              nil
            end
          end
        end
    end
  end
end
