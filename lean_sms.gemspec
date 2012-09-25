# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'lean_sms/version'

Gem::Specification.new do |gem|
  gem.name          = "lean_sms"
  gem.version       = LeanSms::VERSION
  gem.authors       = ["Marcelo Wiermann"]
  gem.email         = ["marcelo.wiermann@gmail.com"]
  gem.description   = %q{LeanSMS is a EventMachine-based SMPP Gateway}
  gem.summary       = %q{LeanSMS is a EventMachine-based SMPP Gateway}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_dependency 'eventmachine'
  gem.add_dependency 'ruby-smpp'
  gem.add_dependency 'em-hiredis'
  gem.add_dependency 'oj'
  gem.add_dependency 'multi_json'

  gem.add_development_dependency 'rspec'
  gem.add_development_dependency 'cucumber'
  gem.add_development_dependency 'guard'
  gem.add_development_dependency 'guard-cucumber'
  gem.add_development_dependency 'guard-rspec'
  gem.add_development_dependency 'factory_girl'
  gem.add_development_dependency 'rack-test'

end
