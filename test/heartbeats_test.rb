require "test_helper"

class HeartbeatsTest < Minitest::Test
  Job = Struct.new(:arguments) do
    def self.name = "DigestJob"
  end

  def test_reads_recurring_yml_per_environment_and_matches_jobs_by_arguments
    Dir.mktmpdir do |dir|
      File.write("#{dir}/recurring.yml", <<~YML)
        production:
          daily_digest:
            class: DigestJob
            args: [ "daily" ]
            schedule: every day at 8:30am Europe/Madrid
          weekly_digest:
            class: DigestJob
            args: [ "weekly" ]
            schedule: every monday at 9am Europe/Madrid
          cleanup:
            command: "SolidQueue::Job.clear_finished_in_batches"
            schedule: every hour
      YML
      tasks = Lince::Heartbeats.recurring_tasks("#{dir}/recurring.yml", "production")
      assert_equal [ "DigestJob" ], tasks.keys, "los «command» no tienen clase: no se pueden seguir"
      assert_equal "weekly_digest", Lince::Heartbeats.task_for(tasks, Job.new([ "weekly" ]))[:key]
      assert_empty Lince::Heartbeats.recurring_tasks("#{dir}/recurring.yml", "staging")
    end
  end

  def test_beat_carries_due_time_and_duration
    client = Class.new { attr_reader :payload; def post(_, p) = @payload = p }.new
    due = Time.utc(2026, 11, 2, 11, 0, 0)
    Lince::Heartbeats.beat("poll", schedule: "every 15 minutes", due_at: due, started_at: due + 2, duration_ms: 720_000.4, client: client).join
    b = client.payload[:beats].first
    assert_equal [ "2026-11-02T11:00:00Z", 720_000 ], [ b[:due_at], b[:duration_ms] ]
  end

  def test_subscription_reports_job_duration_and_due_time
    require "active_support"
    require "active_support/notifications"
    sent = []
    Lince::Heartbeats.singleton_class.alias_method :orig_beat, :beat
    Lince::Heartbeats.define_singleton_method(:beat) { |name, **kw| sent << [ name, kw ] }
    job = Struct.new(:arguments, :scheduled_at, :enqueued_at) { def self.name = "DigestJob" }.new([ "daily" ], nil, Time.utc(2026, 11, 2, 8, 30))
    Lince::Heartbeats.subscribe({ "DigestJob" => [ { key: "daily_digest", schedule: "every day at 8:30am", args: [ "daily" ] } ] })
    ActiveSupport::Notifications.instrument("perform.active_job", job: job) { sleep 0.02 }
    name, kw = sent.first
    assert_equal "daily_digest", name
    assert_equal Time.utc(2026, 11, 2, 8, 30), kw[:due_at]
    assert kw[:duration_ms] >= 20
  ensure
    Lince::Heartbeats.singleton_class.alias_method :beat, :orig_beat
  end
end
