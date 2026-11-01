require "test_helper"
require "active_support/encrypted_configuration"

class CredentialsTest < Minitest::Test
  def test_reads_the_token_from_rails_credentials_without_booting_rails
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p("#{root}/config")
      key = ActiveSupport::EncryptedConfiguration.generate_key
      File.write("#{root}/config/master.key", key)
      ActiveSupport::EncryptedConfiguration.new(config_path: "#{root}/config/credentials.yml.enc", key_path: "#{root}/config/master.key",
        env_key: "NOPE", raise_if_missing_key: true).write("lince:\n  token: secreto123\n")
      assert_equal "secreto123", Lince::Credentials.read(root)
    end
  end
end
