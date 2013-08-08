# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "omf_rc/version"

Gem::Specification.new do |s|
  s.name        = "omf_rc"
  s.version     = OmfRc::VERSION
  s.authors     = ["NICTA"]
  s.email       = ["omf-user@lists.nicta.com.au"]
  s.homepage    = "http://omf.mytestbed.net"
  s.summary     = %q{OMF resource controller}
  s.description = %q{Resource controller of OMF, a generic framework for controlling and managing networking testbeds.}
  s.required_ruby_version = '>= 1.9.3'
  s.license = 'MIT'

  s.rubyforge_project = "omf_rc"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  s.add_development_dependency "minitest", "~> 3.2"
  s.add_development_dependency "em-minitest-spec", "~> 1.1.1"
  s.add_development_dependency "pry"
  s.add_development_dependency "simplecov"
  s.add_runtime_dependency "omf_common", "~> 6.0.2"
  s.add_runtime_dependency "cocaine", "~> 0.3.0"
  s.add_runtime_dependency "mocha"
end
