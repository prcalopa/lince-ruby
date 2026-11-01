require "test_helper"

class InstallerTest < Minitest::Test
  def test_creates_hooks_or_appends_without_touching_what_was_there
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p("#{root}/.kamal/hooks")
      File.write("#{root}/.kamal/hooks/post-deploy", "#!/bin/sh\necho hecho\n")
      Lince::Installer.new(root, out: StringIO.new).run

      pre = File.read("#{root}/.kamal/hooks/pre-deploy")
      assert_match "bundle exec lince deploy started || true", pre
      assert File.executable?("#{root}/.kamal/hooks/pre-deploy")
      post = File.read("#{root}/.kamal/hooks/post-deploy")
      assert post.start_with?("#!/bin/sh\necho hecho\n")
      assert_match "lince deploy finished", post

      Lince::Installer.new(root, out: StringIO.new).run
      assert_equal 1, File.read("#{root}/.kamal/hooks/post-deploy").scan("lince deploy").size, "dos instalaciones no duplican la línea"
    end
  end
end
