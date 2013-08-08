# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "omf_common/version"

Gem::Specification.new do |s|
  s.name        = "omf_common"
  s.version     = OmfCommon::VERSION
  s.authors     = ["NICTA"]
  s.email       = ["omf-user@lists.nicta.com.au"]
  s.homepage    = "http://omf.mytestbed.net"
  s.summary     = %q{Common library of OMF}
  s.description = %q{Common library of OMF, a generic framework for controlling and managing networking testbeds.}
  s.required_ruby_version = '>= 1.9.3'
  s.license = 'MIT'

  s.rubyforge_project = "omf_common"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = ["omf_monitor_topic","omf_send_request", "omf_send_create"]
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  s.add_development_dependency "minitest", "~> 3.2"
  s.add_development_dependency "em-minitest-spec", "~> 1.1.1"
  s.add_development_dependency "simplecov"
  s.add_development_dependency "pry"
  s.add_development_dependency "mocha"

  s.add_runtime_dependency "eventmachine", "= 1.0.3"
  s.add_runtime_dependency "blather", "= 0.8.4"
  s.add_runtime_dependency "logging", "~> 1.7.1"
  s.add_runtime_dependency "hashie", "~> 1.2.0"
  s.add_runtime_dependency "oml4r", "~> 2.9.1"
  s.add_runtime_dependency "json", "~> 1.7.7"
  #s.add_runtime_dependency "json-jwt", "~> 0.5.2"
  #s.add_runtime_dependency "amqp", "~> 1.0.1"
end
