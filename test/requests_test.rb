require "test_helper"

class RequestsTest < Minitest::Test
  class FakeClient
    attr_reader :calls
    def initialize = @calls = []
    def post(path, payload) = (@calls << [ path, payload ]) && true
  end

  def setup
    @now = Time.utc(2026, 11, 2, 10, 0, 30)
    @client = FakeClient.new
    @collector = Lince::Requests::Collector.new(client: @client, interval: 3600, clock: -> { @now })
  end

  def test_counts_status_classes_and_buckets_per_route_and_skips_health
    controller = Struct.new(:action_name) { def self.name = "DealsController" }.new("show")
    app = ->(env) { env["action_controller.instance"] = controller; [ env["PATH_INFO"] == "/boom" ? 500 : 200, {}, [ "ok" ] ] }
    mw = Lince::Requests.new(app, collector: @collector)
    mw.call("PATH_INFO" => "/deals/1")
    mw.call("PATH_INFO" => "/boom")
    mw.call("PATH_INFO" => "/lince/health")
    mw.call("PATH_INFO" => "/up")

    @now += 60
    @collector.flush
    path, payload = @client.calls.first
    assert_equal "/ingest/v1/apps/requests", path
    m = payload[:minutes].first
    assert_equal [ "2026-11-02T10:00:00Z", 2, 1 ], [ m[:minute], m[:total], m[:s5xx] ]
    assert_equal 2, m[:hist].sum
    assert_equal "DealsController#show", m[:routes].first[:route]
    assert_equal 2, m[:routes].first[:count]
  end

  def test_the_current_minute_waits_and_exceptions_count_as_500
    app = ->(_) { raise "boom" }
    mw = Lince::Requests.new(app, collector: @collector)
    assert_raises(RuntimeError) { mw.call("PATH_INFO" => "/x") }
    @collector.flush
    assert_empty @client.calls, "el minuto en curso no se manda"
    @collector.flush(all: true)
    assert_equal 1, @client.calls.first[1][:minutes].first[:s5xx]
  end

  def test_buckets
    assert_equal 0, Lince::Requests.bucket(3)
    assert_equal 4, Lince::Requests.bucket(100)
    assert_equal 11, Lince::Requests.bucket(60_000)
  end
end
