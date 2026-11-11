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

  def gem_line(gem, path, line, method) = "/usr/local/bundle/ruby/4.0.0/gems/#{gem}/#{path}:#{line}:in '#{method}'"

  def test_the_fingerprint_of_errors_with_an_app_frame_does_not_change
    a = Lince::Errors.payload(error_with("x", [ "#{Dir.pwd}/app/models/deal.rb:12:in `total'" ]))
    assert_equal Digest::SHA256.hexdigest("RuntimeError|app/models/deal.rb:`total'")[0, 32], a[:fingerprint], "si cambia, todos los errores vuelven a ser nuevos"
  end

  def test_without_an_app_frame_uses_the_gem_frame_and_where_it_happened
    json = Lince::Errors.payload(error_with("x", [ gem_line("json-3.1.0", "lib/json/common.rb", 297, "JSON.parse") ]), {}, source: "application.active_job")
    json_upgraded = Lince::Errors.payload(error_with("x", [ gem_line("json-3.2.0", "lib/json/common.rb", 301, "JSON.parse") ]), {}, source: "application.active_job")
    pg = Lince::Errors.payload(error_with("x", [ gem_line("pg-1.6.2", "lib/pg/connection.rb", 10, "PG::Connection.new") ]), {}, source: "application.active_job")
    runner = Lince::Errors.payload(error_with("x", [ gem_line("json-3.1.0", "lib/json/common.rb", 297, "JSON.parse") ]), {}, source: "application.runner.railties")
    assert_equal json[:fingerprint], json_upgraded[:fingerprint], "ni la versión de la gema ni la línea"
    refute_equal json[:fingerprint], pg[:fingerprint], "dos RuntimeError de gemas distintas no son el mismo error"
    refute_equal json[:fingerprint], runner[:fingerprint]
    assert_equal "gems/json/lib/json/common.rb:297 en 'JSON.parse'", json[:location]
    assert_equal "Active Job", json[:context]
    assert_equal "rails runner", runner[:context]
  end

  def named_error(name, backtrace)
    Class.new(StandardError) { define_singleton_method(:name) { name } }.new("x").tap { it.set_backtrace(backtrace) }
  end

  def test_ignores_bot_noise_raised_outside_the_app
    with_buffer do |buffer|
      sub = Lince::Errors::Subscriber.new
      sub.report(named_error("ActionDispatch::RemoteIp::IpSpoofAttackError", [ gem_line("actionpack-8.1.4", "lib/x.rb", 1, "call") ]), handled: false, severity: :error, context: {})
      sub.report(named_error("URI::InvalidURIError", [ gem_line("uri-1.1.1", "lib/uri.rb", 1, "parse") ]), handled: false, severity: :error, context: {})
      assert_equal 0, buffer.size
      sub.report(named_error("URI::InvalidURIError", [ "#{Dir.pwd}/app/models/link.rb:3:in `url'" ]), handled: false, severity: :error, context: {})
      assert_equal 1, buffer.size, "desde la app sí es un fallo"
    end
  end

  class FlakyClient
    attr_accessor :up
    attr_reader :calls
    def initialize = (@calls = []) && (@up = false)
    def post(path, payload) = (@calls << payload) && @up
  end

  def test_keeps_batches_lince_did_not_receive_and_resends_them_in_order_with_the_same_id
    now = Time.now
    client = FlakyClient.new
    buffer = Lince::Errors::Buffer.new(client: client, interval: 3600, clock: -> { now })
    buffer.add(Lince::Errors.payload(error_with("a", [ "#{Dir.pwd}/app/a.rb:1:in `a'" ])))
    buffer.flush
    assert_equal 1, buffer.pending
    first = client.calls.last[:batch]

    buffer.add(Lince::Errors.payload(error_with("b", [ "#{Dir.pwd}/app/b.rb:1:in `b'" ])))
    buffer.flush
    assert_equal first, client.calls.last[:batch], "el nuevo espera detrás del pendiente"
    assert_equal 2, buffer.pending

    client.up = true
    buffer.flush
    assert_equal [ first, first, first ], client.calls.first(3).map { it[:batch] }
    assert_equal 0, buffer.pending
    refute_equal first, client.calls.last[:batch]
  end

  def test_gives_up_on_a_batch_after_an_hour
    now = Time.now
    client = FlakyClient.new
    buffer = Lince::Errors::Buffer.new(client: client, interval: 3600, clock: -> { now })
    buffer.add(Lince::Errors.payload(error_with("a", [ "#{Dir.pwd}/app/a.rb:1:in `a'" ])))
    buffer.flush
    now += Lince::Errors::Buffer::KEEP + 1
    buffer.flush
    assert_equal 0, buffer.pending
  end
end
