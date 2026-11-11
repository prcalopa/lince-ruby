require "digest"
require "securerandom"

module Lince
  # Errores de producción: se suscribe al error reporter de Rails, agrupa por huella en memoria y manda lotes
  # a Lince cada pocos segundos desde un hilo aparte. Nunca manda parámetros, cuerpos ni cabeceras.
  module Errors
    IGNORED = %w[
      ActiveRecord::RecordNotFound ActionController::RoutingError ActionController::InvalidAuthenticityToken
      ActionController::BadRequest ActionController::UnknownFormat ActionController::ParameterMissing
      ActionDispatch::Http::MimeNegotiation::InvalidType ActionDispatch::Http::Parameters::ParseError
      AbstractController::ActionNotFound Rack::Timeout::RequestTimeoutException
      ActionDispatch::RemoteIp::IpSpoofAttackError
    ].freeze
    # Sin ninguna línea de la app son peticiones mal formadas de bots (/wp-admin/…), no fallos de la app.
    IGNORED_OUTSIDE_APP = %w[URI::InvalidURIError].freeze
    RUNNER_SOURCE = "application.runner.railties".freeze # lo que llega sin capturar hasta `rails runner`

    class Subscriber
      def report(error, handled:, severity:, context:, source: nil)
        return unless severity == :error
        return if source == Errors::RUNNER_SOURCE && !Lince.config.runner_errors
        return if (Errors::IGNORED + Lince.config.ignored_errors).include?(error.class.name)
        return if Errors::IGNORED_OUTSIDE_APP.include?(error.class.name) && Errors.app_frame(error).nil?
        Errors.buffer.add(Errors.payload(error, context, source: source))
      rescue StandardError
        nil # Lince nunca puede romper la app
      end
    end

    class Buffer
      MAX = 200
      KEEP = 3600 # un lote que Lince no recibe se reintenta, en orden y con el mismo id, durante una hora
      PENDING = 30

      def initialize(client: nil, interval: 10, clock: -> { Time.now })
        @client, @interval, @clock, @items, @pending, @mutex = client, interval, clock, {}, [], Mutex.new
      end

      def add(item)
        @mutex.synchronize do
          if (existing = @items[item[:fingerprint]])
            existing[:count] += 1
            existing[:at] = item[:at]
          elsif @items.size < MAX
            @items[item[:fingerprint]] = item
          end
        end
        ensure_thread
      end

      # Primero lo que quedó pendiente; si Lince no responde, el lote nuevo espera detrás. Lince descarta un id que ya
      # recibió: si contestó tarde pero lo guardó, reintentar no cuenta dos veces.
      def flush
        batches = @mutex.synchronize do
          @pending << { id: SecureRandom.uuid, errors: @items.values, since: @clock.call } if @items.any?
          @items = {}
          @pending.reject! { @clock.call - it[:since] > KEEP }
          @pending.shift(@pending.size - PENDING) if @pending.size > PENDING
          @pending.dup
        end
        batches.each do |batch|
          break unless (@client || Lince.client).post("/ingest/v1/apps/errors", { batch: batch[:id], errors: batch[:errors] })
          @mutex.synchronize { @pending.delete(batch) }
        end
      end

      def size = @mutex.synchronize { @items.size }
      def pending = @mutex.synchronize { @pending.size }

      private
        # Un hilo por proceso (Puma hace fork): si cambia el pid, se arranca otro.
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

    module_function

    def buffer = @buffer ||= Buffer.new

    # Huella: clase y primera línea de la app sin el número. Sin línea de la app (el error salta en una gema o en
    # Rails), la primera línea de fuera de Ruby sin la versión de la gema, y dónde pasó: si no, todos los
    # NoMethodError de gemas de un proyecto serían el mismo error.
    def payload(error, context = {}, source: nil)
      frame = app_frame(error)
      where = describe(context) || SOURCES[source]
      key = frame ? [ error.class.name, frame.sub(/:\d+:in /, ":") ] : [ error.class.name, gem_frame(error)&.sub(/:\d+:in /, ":"), where ]
      { fingerprint: Digest::SHA256.hexdigest(key.join("|"))[0, 32],
        class: error.class.name, message: Scrubber.scrub(error.message), location: (frame || gem_frame(error))&.sub(/:in /, " en "),
        context: where, backtrace: (error.backtrace || []).first(20).map { relative(it) },
        release: Health.revision, count: 1, at: Time.now.utc.iso8601 }
    end

    SOURCES = { RUNNER_SOURCE => "rails runner", "application.active_job" => "Active Job", "application.action_dispatch" => "Rails (middleware)" }.freeze

    # La primera línea de una gema, como «gems/json/lib/json/common.rb:297:in …» (sin la ruta ni la versión); si no
    # hay, la primera.
    def gem_frame(error)
      backtrace = error.backtrace || []
      line = backtrace.find { it.include?("/gems/") } || backtrace.first
      line && relative(line).sub(%r{\A.*/gems/([a-z0-9_.-]+?)-\d[\w.]*/}i, 'gems/\\1/')
    end

    # Primera línea del backtrace que es código de la app (no de gemas).
    def app_frame(error)
      line = (error.backtrace || []).find { |l| relative(l).start_with?("app/", "lib/", "config/") && !l.include?("/gems/") }
      line && relative(line)
    end

    def relative(line)
      root = defined?(Rails) && Rails.respond_to?(:root) && Rails.root ? "#{Rails.root}/" : "#{Dir.pwd}/"
      line.to_s.delete_prefix(root)
    end

    # Controlador#acción o la clase del job, sin datos de la petición.
    def describe(context)
      ctx = (defined?(ActiveSupport::ExecutionContext) ? ActiveSupport::ExecutionContext.to_h : {}).merge(context || {})
      if (controller = ctx[:controller]).respond_to?(:action_name)
        "#{controller.class.name}##{controller.action_name}"
      elsif (job = ctx[:job])
        job.class.name
      end
    end
  end
end
