# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'capistrano-jdk-installer/version'

Gem::Specification.new do |gem|
  gem.name          = "capistrano-jdk-installer"
  gem.version       = Capistrano::JDKInstaller::VERSION
  gem.authors       = ["Yamashita Yuu"]
  gem.email         = ["yamashita@geishatokyo.com"]
  gem.description   = %q{a capistrano recipe to download and install JDK for your projects.}
  gem.summary       = %q{a capistrano recipe to download and install JDK for your projects.}
  gem.homepage      = "https://github.com/yyuu/capistrano-jdk-installer"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_dependency("capistrano", "< 3")
  gem.add_dependency("capistrano-file-transfer-ext", ">= 0.1.0")
  gem.add_dependency("json")
  gem.add_dependency("mechanize", "~> 2.5.0")
end
