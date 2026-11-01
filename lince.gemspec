require_relative "lib/lince/version"

Gem::Specification.new do |spec|
  spec.name = "lince"
  spec.version = Lince::VERSION
  spec.authors = [ "Pere Calopa" ]
  spec.summary = "Cliente de Lince para apps Rails: /lince/health y avisos de despliegue desde Kamal"
  spec.homepage = "https://github.com/prcalopa/lince-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"
  spec.files = Dir["lib/**/*.rb", "exe/*", "README.md", "LICENSE"]
  spec.bindir = "exe"
  spec.executables = [ "lince" ]
  spec.metadata["rubygems_mfa_required"] = "true"
end
