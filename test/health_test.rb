require "test_helper"

class HealthTest < Minitest::Test
  APP = ->(_env) { [ 200, {}, [ "app" ] ] }

  def setup = Lince.config.token = "tok-123"
  def teardown = Lince.config.token = nil

  def call(path, method = "GET", token: "tok-123")
    Lince::Health.new(APP).call("PATH_INFO" => path, "REQUEST_METHOD" => method, "HTTP_AUTHORIZATION" => ("Bearer #{token}" if token))
  end

  def test_without_the_token_it_does_not_exist
    assert_equal 404, call("/lince/health", token: nil)[0]
    assert_equal 404, call("/lince/health", token: "otro")[0]
    Lince.config.token = ""
    assert_equal 404, call("/lince/health", token: "")[0], "sin token configurado, nadie la lee"
  end

  def test_answers_on_its_path_and_passes_the_rest
    status, headers, body = call("/lince/health")
    assert_equal 200, status
    assert_equal "application/json", headers["content-type"]
    data = JSON.parse(body.first)
    assert_equal "ok", data["status"]
    assert_equal Lince::VERSION, data["lince"]
    assert_kind_of Hash, data["metrics"]
    assert data["metrics"]["disk_free_pct"].between?(0, 100), "df funciona"

    assert_equal [ "app" ], call("/otra")[2]
    assert_equal [ "app" ], call("/lince/health", "POST")[2]
  end

  def test_reports_the_deployed_version
    ENV["KAMAL_VERSION"] = "abc123"
    assert_equal "abc123", JSON.parse(call("/lince/health")[2].first)["version"]
  ensure
    ENV.delete("KAMAL_VERSION")
  end
end
