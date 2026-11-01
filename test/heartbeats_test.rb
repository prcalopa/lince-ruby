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
end
