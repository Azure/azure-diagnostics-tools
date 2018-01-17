Gem::Specification.new do |s|
  s.name            = 'logstash-input-azurewadtable'
  s.version         = '0.9.13'
  s.licenses        = ['Apache License (2.0)']
  s.summary         = "This plugin collects Microsoft Azure Diagnostics data from Azure Storage Tables."
  s.description     = "This gem is a Logstash plugin. It reads and parses diagnostics data from Azure Storage Tables."
  s.authors         = ["Microsoft Corporation"]
  s.email           = 'azdiag@microsoft.com'
  s.homepage        = "https://github.com/Azure/azure-diagnostics-tools"
  s.require_paths   = ["lib"]

  # Files
  s.files = Dir['lib/**/*','spec/**/*','vendor/**/*','*.gemspec','*.md','Gemfile','LICENSE']
   # Tests
  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  # Special flag to let us know this is actually a logstash plugin
  s.metadata = { "logstash_plugin" => "true", "logstash_group" => "input" }

  # Gem dependencies
  s.add_runtime_dependency "logstash-core-plugin-api", ">= 1.60", "<= 2.99"
  s.add_runtime_dependency 'azure-storage', '~> 0.13.0.preview'
  s.add_development_dependency 'logstash-devutils', '>= 1.1.0'
end

