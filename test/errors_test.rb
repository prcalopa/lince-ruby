require "test_helper"

class ErrorsTest < Minitest::Test
  class FakeClient
    attr_reader :calls
    def initialize = @calls = []
    def post(path, payload) = (@calls << [ path, payload ]) && true
  end

  def error_with(message, backtrace)
    RuntimeError.new(message).tap { |e| e.set_backtrace(backtrace) }
  end

  def test_groups_by_class_and_first_app_frame_ignoring_the_line_number
    a = Lince::Errors.payload(error_with("uno", [ "/gems/rack/x.rb:1:in `call'", "#{Dir.pwd}/app/models/deal.rb:12:in `total'" ]))
    b = Lince::Errors.payload(error_with("dos", [ "#{Dir.pwd}/app/models/deal.rb:15:in `total'" ]))
    assert_equal a[:fingerprint], b[:fingerprint], "mover la línea no crea otro error"
    assert_equal "app/models/deal.rb:12 en `total'", a[:location]
  end

  def test_scrubs_personal_data_and_secrets_from_messages
    msg = Lince::Scrubber.scrub("No user pere@example.com id 12345678 token=abc123 at https://x.com/a?email=y key AbCdEfGhIjKlMnOpQrStUvWxYz0123456789")
    refute_match "pere@example.com", msg
    refute_match "12345678", msg
    refute_match "abc123", msg
    refute_match "email=y", msg
    refute_match "AbCdEfGh", msg
  end

  def test_buffer_counts_repeats_and_sends_one_batch
    client = FakeClient.new
    buffer = Lince::Errors::Buffer.new(client: client, interval: 3600)
    item = Lince::Errors.payload(error_with("x", [ "#{Dir.pwd}/app/a.rb:1:in `b'" ]))
    3.times { buffer.add(item.dup) }
    buffer.flush
    assert_equal 1, client.calls.size
    path, payload = client.calls.first
    assert_equal "/ingest/v1/apps/errors", path
    assert_equal 3, payload[:errors].first[:count]
    buffer.flush
    assert_equal 1, client.calls.size, "sin errores no manda nada"
  end

  def test_subscriber_skips_ignored_and_non_error_severities
    before = Lince::Errors.buffer.size
    sub = Lince::Errors::Subscriber.new
    sub.report(RuntimeError.new("aviso"), handled: true, severity: :warning, context: {})
    not_found = Class.new(StandardError) { def self.name = "ActiveRecord::RecordNotFound" }
    sub.report(not_found.new, handled: false, severity: :error, context: {})
    assert_equal before, Lince::Errors.buffer.size
  end

  def with_buffer
    original = Lince::Errors.buffer
    buffer = Lince::Errors::Buffer.new(client: FakeClient.new, interval: 3600)
    Lince::Errors.instance_variable_set(:@buffer, buffer)
    yield buffer
  ensure
    Lince::Errors.instance_variable_set(:@buffer, original)
  end

  def with_runner_errors(value)
    original = Lince.config.runner_errors
    Lince.config.runner_errors = value
    yield
  ensure
    Lince.config.runner_errors = original
  end

  def report_from(source)
    Lince::Errors::Subscriber.new.report(error_with("x", [ "runner_command.rb:49:in `<main>'" ]), handled: false, severity: :error, context: {}, source: source)
  end

  def test_runner_errors_are_off_unless_the_env_turns_them_on
    original = ENV.delete("LINCE_RUNNER_ERRORS")
    refute Lince::Configuration.new.runner_errors
    ENV["LINCE_RUNNER_ERRORS"] = "true"
    assert Lince::Configuration.new.runner_errors
  ensure
    original ? ENV["LINCE_RUNNER_ERRORS"] = original : ENV.delete("LINCE_RUNNER_ERRORS")
  end

  def test_subscriber_skips_rails_runner_errors_by_default
    with_buffer do |buffer|
      with_runner_errors(false) { report_from("application.runner.railties") }
      assert_equal 0, buffer.size
    end
  end

  def test_subscriber_reports_rails_runner_errors_when_enabled
    with_buffer do |buffer|
      with_runner_errors(true) { report_from("application.runner.railties") }
      assert_equal 1, buffer.size
    end
  end

  def test_subscriber_keeps_reporting_errors_from_other_sources
    with_buffer do |buffer|
      with_runner_errors(false) { report_from("application.active_job") }
      assert_equal 1, buffer.size
    end
  end
end
