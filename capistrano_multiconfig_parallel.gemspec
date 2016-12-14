require File.expand_path('../lib/capistrano_multiconfig_parallel/version', __FILE__)

Gem::Specification.new do |s|
  s.name = 'capistrano_multiconfig_parallel'
  s.version = CapistranoMulticonfigParallel.gem_version
  s.platform = Gem::Platform::RUBY
  s.description = 'CapistranoMulticonfigParallel is a simple ruby implementation that allows you to run multiple tasks in parallel for single or multiple applications and uses websockets for inter-process communication and has a interactive menu'
  s.email = 'raoul_ice@yahoo.com'
  s.homepage = 'http://github.com/bogdanRada/capistrano_multiconfig_parallel/'
  s.summary = 'CapistranoMulticonfigParallel is a simple ruby implementation that allows you to run multiple tasks in parallel and uses websockets for inter-process communication and has a interactive menu'
  s.authors = ['bogdanRada']
  s.date = Date.today

  s.licenses = ['MIT']
  s.files = `git ls-files`.split("\n")
  s.test_files = s.files.grep(/^(spec)/)
  s.require_paths = ['lib']
  s.executables = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.required_ruby_version = '>= 2.0'

  s.add_runtime_dependency 'celluloid', '>= 0.16', '>= 0.16'
  s.add_runtime_dependency 'celluloid-pmap', '~> 0.2', '>= 0.2.2'
  s.add_runtime_dependency 'celluloid_pubsub', '~> 1.1', '>= 1.1.0'
  s.add_runtime_dependency 'composable_state_machine', '~> 1.0', '>= 1.0.2'
  s.add_runtime_dependency 'terminal-table', '~> 1.7', '>= 1.7.3'
  s.add_runtime_dependency 'colorize', '~>  0.8', '>= 0.8.1'
  s.add_runtime_dependency 'eventmachine', '~> 1.2', '>= 1.2.1'
  s.add_runtime_dependency 'right_popen', '~> 3.0', '>= 3.0.1'
  s.add_runtime_dependency 'activesupport',  '>= 4.0','>= 4.0'
  s.add_runtime_dependency 'configliere', '~> 0.4', '>=0.4'
  s.add_runtime_dependency 'inquirer', '~> 0.2', '>= 0.2'
  s.add_runtime_dependency 'devnull','~> 0.1', '>= 0.1'
  s.add_runtime_dependency 'capistrano_sentinel',  '~> 0.2', '>= 0.2.0'
  s.add_runtime_dependency 'powerbar', '~> 1.0', '>= 1.0.17'

  s.add_development_dependency 'rake', '~> 12.0', '>= 12.0'
  s.add_development_dependency 'rspec', '~> 3.5', '>= 3.5'
  s.add_development_dependency 'simplecov', '~> 0.12', '>= 0.12'
  s.add_development_dependency 'simplecov-summary', '~> 0.0.5', '>= 0.0.5'
  s.add_development_dependency 'mocha', '~> 1.2', '>= 1.2'
  s.add_development_dependency 'coveralls', '~> 0.8', '>= 0.8'

  s.add_development_dependency 'yard', '~> 0.8', '>= 0.8.7'
  s.add_development_dependency 'redcarpet', '~> 3.3', '>= 3.3'
  s.add_development_dependency 'github-markup', '~> 1.4', '>= 1.4'
  s.add_development_dependency 'inch', '~> 0.7', '>= 0.7'
end
