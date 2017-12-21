Gem::Specification.new do |s|
  s.name          = 'logstash-input-azureblob'
  s.version       = '0.9.13'
  s.platform      = 'java'
  s.licenses      = ['Apache-2.0']
  s.summary       = 'This plugin collects Microsoft Azure Diagnostics data from Azure Storage Blobs.'
  s.description   = 'This gem is a Logstash plugin. It reads and parses data from Azure Storage Blobs.'
  s.homepage      = 'https://github.com/Azure/azure-diagnostics-tools'
  s.authors       = ['Microsoft Corporation']
  s.email         = 'azdiag@microsoft.com'
  s.require_paths = ['lib']

  # Files
  s.files = Dir['lib/**/*', 'spec/**/*', 'vendor/**/*', '*.gemspec', '*.md', 'Gemfile', 'LICENSE']
  # Tests
  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  # Special flag to let us know this is actually a logstash plugin
  s.metadata = { 'logstash_plugin' => 'true', 'logstash_group' => 'input' }

  # Gem dependencies
  s.add_runtime_dependency 'logstash-core-plugin-api', '>= 1.60', '<= 2.99'
  s.add_runtime_dependency 'logstash-codec-json_lines', '~> 3'
  s.add_runtime_dependency 'stud', '~> 0.0', '>= 0.0.22'
  s.add_runtime_dependency 'azure-storage', '~> 0.15.0.preview'
  s.add_development_dependency 'logstash-devutils', '~> 1'
  s.add_development_dependency 'logging', '~> 2'

  # Jar dependencies
  s.requirements << "jar 'org.glassfish:javax.json', '1.1'"
  s.add_runtime_dependency 'jar-dependencies', '~> 0'
end
