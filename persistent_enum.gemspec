# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'persistent_enum/version'

Gem::Specification.new do |spec|
  spec.name          = "persistent_enum"
  spec.version       = PersistentEnum::VERSION
  spec.authors       = ["Cerego"]
  spec.email         = ["edge-usa@cerego.com"]
  spec.summary       = "Database-backed enums for Rails"
  spec.description   = "Provide a database-backed enumeration between indices and symbolic values. This allows us to have a valid foreign key which behaves like a enumeration. Values are cached at startup, and cannot be changed."
  spec.homepage      = "http://www.cerego.com"
  spec.license       = "BSD-2-Clause"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.0"
  spec.add_development_dependency "rake", "~> 10.0"

  spec.add_dependency "activerecord", "~> 4.0"
  spec.add_dependency "activesupport", "~> 4.0"
end
