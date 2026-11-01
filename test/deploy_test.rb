require "test_helper"

class DeployTest < Minitest::Test
  class FakeClient
    attr_reader :calls
    def initialize = @calls = []
    def post(path, payload) = (@calls << [ path, payload ]) && true
  end

  def test_sends_what_kamal_puts_in_the_environment
    client = FakeClient.new
    env = { "KAMAL_VERSION" => "9d9267f", "KAMAL_PERFORMER" => "pere", "KAMAL_HOSTS" => "1.2.3.4", "KAMAL_RUNTIME" => "" }
    assert Lince::Deploy.notify("finished", env, client: client)
    path, payload = client.calls.first
    assert_equal "/ingest/v1/apps/deployments", path
    assert_equal({ event: "finished", version: "9d9267f", performer: "pere", hosts: "1.2.3.4", lince: Lince::VERSION }, payload)
  end

  def test_without_version_it_does_nothing_and_unknown_events_fail_loudly
    client = FakeClient.new
    refute Lince::Deploy.notify("started", {}, client: client)
    assert_empty client.calls
    assert_raises(ArgumentError) { Lince::Deploy.notify("exploded", { "KAMAL_VERSION" => "x" }, client: client) }
  end

  def test_client_never_raises_without_token_or_connection
    config = Lince::Configuration.new
    config.token = ""
    refute Lince::Client.new(config).post("/x", {})
    config.token = "t"
    config.endpoint = "http://127.0.0.1:1"
    refute Lince::Client.new(config).post("/x", {})
  end
end
