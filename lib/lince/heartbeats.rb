require "yaml"
require "time"
require "erb"

module Lince
  # Latidos: cada trabajo recurrente de Solid Queue (config/recurring.yml) avisa al terminar, con su horario,
  # para que Lince sepa cuándo toca el siguiente. Para crons de fuera: Lince.heartbeat("backup", schedule: "every day at 3am").
  module Heartbeats
    module_function

    # due_at: la hora a la que tocaba (la del horario, no la de fin); duration_ms: lo que ha tardado.
    def beat(name, schedule: nil, status: "ok", due_at: nil, started_at: nil, duration_ms: nil, client: Lince.client)
      beat = { name: name.to_s, schedule: schedule, status: status, at: Time.now.utc.iso8601,
               due_at: due_at&.utc&.iso8601, started_at: started_at&.utc&.iso8601, duration_ms: duration_ms&.round }.compact
      Thread.new { client.post("/ingest/v1/apps/heartbeats", { beats: [ beat ] }) } # sin bloquear el job
    end

    # { "JobClass" => [{ key:, schedule:, args: }] } de config/recurring.yml para el entorno actual.
    def recurring_tasks(path, env)
      return {} unless File.exist?(path)
      data = YAML.safe_load(ERB.new(File.read(path)).result, aliases: true) || {}
      # Con secciones por entorno (production:, development:) o plano, como lo acepte Solid Queue.
      tasks = data[env].is_a?(Hash) ? data[env] : (data.values.all? { |v| v.is_a?(Hash) && v.key?("schedule") } ? data : {})
      tasks.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(key, task), map|
        next unless task.is_a?(Hash) && task["class"] && task["schedule"]
        map[task["class"]] << { key: key, schedule: task["schedule"], args: task["args"] }
      end
    rescue StandardError
      {}
    end

    # El task que corresponde a un job: por clase y, si hay varios, por argumentos.
    def task_for(tasks, job)
      candidates = tasks.fetch(job.class.name, [])
      candidates.find { |t| t[:args].nil? ? candidates.one? : Array(t[:args]) == job.arguments } || (candidates.first if candidates.one?)
    end

    def subscribe(tasks)
      return if tasks.empty?
      ActiveSupport::Notifications.subscribe("perform.active_job") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        job = event.payload[:job]
        task = job && task_for(tasks, job)
        next unless task
        started = Time.now - event.duration / 1000.0
        due = [ job.scheduled_at, job.enqueued_at ].compact.map { it.is_a?(String) ? Time.parse(it) : it }.first
        beat(task[:key], schedule: task[:schedule], status: event.payload[:exception_object] ? "failed" : "ok",
          due_at: due, started_at: started, duration_ms: event.duration)
      rescue StandardError
        nil
      end
    end
  end

  # Para crons de fuera: Lince.heartbeat("backup", schedule: "every day at 3am", duration_ms: …).
  def self.heartbeat(name, schedule: nil, status: "ok", duration_ms: nil) = Heartbeats.beat(name, schedule: schedule, status: status, duration_ms: duration_ms)
end
