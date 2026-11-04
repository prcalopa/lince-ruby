require "digest"

module Lince
  # Errores de producción: se suscribe al error reporter de Rails, agrupa por huella en memoria y manda lotes
  # a Lince cada pocos segundos desde un hilo aparte. Nunca manda parámetros, cuerpos ni cabeceras.
  module Errors
    IGNORED = %w[
      ActiveRecord::RecordNotFound ActionController::RoutingError ActionController::InvalidAuthenticityToken
      ActionController::BadRequest ActionController::UnknownFormat ActionController::ParameterMissing
      ActionDispatch::Http::MimeNegotiation::InvalidType ActionDispatch::Http::Parameters::ParseError
      AbstractController::ActionNotFound Rack::Timeout::RequestTimeoutException
    ].freeze
    RUNNER_SOURCE = "application.runner.railties".freeze # lo que llega sin capturar hasta `rails runner`

    class Subscriber
      def report(error, handled:, severity:, context:, source: nil)
        return unless severity == :error
        return if source == Errors::RUNNER_SOURCE && !Lince.config.runner_errors
        return if (Errors::IGNORED + Lince.config.ignored_errors).include?(error.class.name)
        Errors.buffer.add(Errors.payload(error, context))
      rescue StandardError
        nil # Lince nunca puede romper la app
      end
    end

    class Buffer
      MAX = 200

      def initialize(client: nil, interval: 10)
        @client, @interval, @items, @mutex = client, interval, {}, Mutex.new
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

      def flush
        batch = @mutex.synchronize { @items.values.tap { @items = {} } }
        (@client || Lince.client).post("/ingest/v1/apps/errors", { errors: batch }) if batch.any?
      end

      def size = @mutex.synchronize { @items.size }

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

    def payload(error, context = {})
      frame = app_frame(error)
      { fingerprint: Digest::SHA256.hexdigest([ error.class.name, frame&.sub(/:\d+:in /, ":") ].join("|"))[0, 32],
        class: error.class.name, message: Scrubber.scrub(error.message), location: frame&.sub(/:in /, " en "),
        context: describe(context), backtrace: (error.backtrace || []).first(20).map { relative(it) },
        release: Health.revision, count: 1, at: Time.now.utc.iso8601 }
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
