require "test_helper"

class HealthTest < Minitest::Test
  APP = ->(_env) { [ 200, {}, [ "app" ] ] }

  def call(path, method = "GET") = Lince::Health.new(APP).call("PATH_INFO" => path, "REQUEST_METHOD" => method)

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
