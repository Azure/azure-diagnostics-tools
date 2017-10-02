Gem::Specification.new do |s|
  s.name          = 'logstash-input-azureeventhub'
  s.version       = '0.9.8'
  s.platform      = "java"
  s.licenses      = ['Apache License (2.0)']
  s.summary       = "This plugin collects data from Azure Event Hubs."
  s.description   = "This gem is a Logstash plugin. It reads data from Azure Event Hubs."
  s.authors       = ["Microsoft Corporation"]
  s.email         = 'azdiag@microsoft.com'
  s.homepage      = "https://github.com/Azure/azure-diagnostics-tools"
  s.require_paths = ["lib"]

  # Files
  s.files = Dir['lib/**/*','spec/**/*','vendor/**/*','*.gemspec','*.md','Gemfile','LICENSE']
  # Tests
  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  # Special flag to let us know this is actually a logstash plugin
  s.metadata = { "logstash_plugin" => "true", "logstash_group" => "input" }

  # Gem dependencies
  s.add_runtime_dependency "logstash-core-plugin-api", ">= 1.60", "<= 2.99"
  s.add_runtime_dependency 'azure', '~> 0.7.1'
    s.add_development_dependency 'logstash-devutils'
  
  #Jar dependencies
  s.requirements << "jar 'com.microsoft.azure:azure-eventhubs', '0.15.0'"
  s.add_runtime_dependency 'jar-dependencies', '~> 0.3.2'
end
