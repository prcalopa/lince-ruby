require "json"
require "net/http"
require "uri"

module Lince
  # POST a Lince. Nunca lanza: si Lince no está, la app y el deploy siguen.
  class Client
    def initialize(config)
      @config = config
    end

    def post(path, payload)
      return warn_once("sin token: configura lince.token en las credenciales o LINCE_TOKEN") if @config.token.to_s.empty?
      uri = URI.join(@config.endpoint, path)
      req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "Authorization" => "Bearer #{@config.token}", "User-Agent" => "lince-ruby/#{VERSION}")
      req.body = JSON.generate(payload)
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: @config.timeout, read_timeout: @config.timeout) { |http| http.request(req) }
      return true if res.is_a?(Net::HTTPSuccess)
      warn_once("Lince respondió #{res.code} en #{uri.path}")
    rescue StandardError => e
      warn_once("no se pudo avisar a Lince: #{e.class}: #{e.message}")
    end

    private
      def warn_once(message)
        $stderr.puts("[lince] #{message}")
        false
      end
  end
end
