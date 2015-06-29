capistrano_multiconfig_parallel
==================

[![Gem Version](https://badge.fury.io/rb/capistrano_multiconfig_parallel.svg)](http://badge.fury.io/rb/capistrano_multiconfig_parallel)
[![Repo Size](https://reposs.herokuapp.com/?path=bogdanRada/capistrano_multiconfig_parallel)](https://github.com/bogdanRada/capistrano_multiconfig_parallel)
[![Gem Downloads](https://ruby-gem-downloads-badge.herokuapp.com/capistrano_multiconfig_parallel?type=total&style=dynamic)](https://github.com/bogdanRada/capistrano_multiconfig_parallel)
[![Maintenance Status](http://stillmaintained.com/bogdanRada/capistrano_multiconfig_parallel.png)](https://github.com/bogdanRada/capistrano_multiconfig_parallel)

Description
--------
CapistranoMulticonfigParallel is a simple ruby implementation that allows you to run multiple tasks in parallel for multiple applications and uses websockets for inter-process communication and has a interactive menu

IMPORTANT!  The whole reason for this gem was for using [Caphub][caphub]  in a more easy way and allowing you to run tasks in parallel for multiple aplications . 
However this can be used for normal applications also, if you want for example to deploy your app to multiple sandboxes on development environment
or even deploy in parallel to multiple stages.

CAUTION!! PLEASE READ CAREFULLY!! Capistrano is not thread-safe. However in order to work around this problem, each of the task is executing inside a thread that spawns a new process in order to run capistrano tasks
The thread monitors the process. This works well, however if the tasks you are executing is working with files, you might get into deadlocks because multiple proceses try to access same resource.
Instead of using files , please consider using StringIO instead. 

[caphub]: https://github.com/railsware/caphub

Requirements
--------
1.  [Ruby 1.9.x or Ruby 2.x.x][ruby]
2. [ActiveSuport >= 4.2.0][activesupport]
3. [celluloid-pmap >= 0.2.0][celluloid_pmap]
5. [composable_state_machine >= 1.0.2][composable_state_machine]
6. [terminal-table >= 1.4.5][terminal_table]
7. [formatador >= 0.2.5] [formatador]
8. [colorize] [colorize]
9. [eventmachine >= 1.0.7] [eventmachine]
10. [right_popen >= 1.1.3] [right_popen]
11. [capistrano-multiconfig >= 3.0.8] [capistrano-multiconfig]
12. [capistrano >= 3.0] [capistrano]
13. [configliere >= 0.4] [configliere]
14.  [inquirer >= 0.2] [inquirer]

[ruby]: http://www.ruby-lang.org
[activesupport]:https://rubygems.org/gems/activesupport
[capistrano_multiconfig_parallel]:https://github.com/bogdanRada/capistrano_multiconfig_parallel
[celluloid_pmap]:https://github.com/jwo/celluloid-pmap
[composable_state_machine]: https://github.com/swoop-inc/composable_state_machine
[terminal_table]: https://github.com/tj/terminal-table
[formatador]: https://github.com/geemus/formatador
[colorize]: https://github.com/fazibear/colorize
[eventmachine]: https://github.com/eventmachine/eventmachine
[right_popen]: https://github.com/rightscale/right_popen
[capistrano-multiconfig]: https://github.com/railsware/capistrano-multiconfig
[capistrano]: https://github.com/capistrano/capistrano/
[configliere]: https://github.com/infochimps-platform/configliere
[inquirer]: https://github.com/arlimus/inquirer.rb

Compatibility
--------

Rails >3.0 only. MRI 1.9.x, 2.x

Ruby 1.8 is not officially supported. We will accept further compatibilty pull-requests but no upcoming versions will be tested against it.

Rubinius and Jruby  support temporarily dropped due to Rails 4 incompatibility.

Installation Instructions
--------

Add the following to your Gemfile:
  
```ruby
  gem "capistrano_multiconfig_parallel"
```


Add the following to your Capfile:
  
```ruby
  require 'capistrano_multiconfig_parallel'
```

Please read  [Release Details][release-details] if you are upgrading. We break backward compatibility between large ticks but you can expect it to be specified at release notes.
[release-details]: https://github.com/bogdanRada/capistrano_multiconfig_parallel/releases

Default Configuration:
--------

```ruby
CapistranoMulticonfigParallel.configure do |c|
   c.task_confirmations = ['deploy:symlink:release']
        c.task_confirmation_active = false
        c.track_dependencies = false
        c.websocket_server = { enable_debug: false }
        c.development_stages = ['development', 'webdev']
end
```
```
{{ lib/capistrano_multiconfig_parallel/initializers/default.yml }}
```
 Available command line  options when executing a command
--------

--multi-debug
   If option is present , will enable debugging of workers

--multi-progress
  If option is present will first execute before any process , same task but with option "--dry-run" in order to show progress of how many tasks are in total for that task and what is the progress of executing
 This will slow down the workers , because they will execute twice the same task.

--multi-secvential
  If parallel executing does not work for you, you can use this option so that each process is executed normally and ouputted to the screen.
  However this means that all other tasks will have to wait for each other to finish before starting 


Usage Instructions
--------

[![capistrano multiconfig parallel ](img/parallel_demo.png)](#features)

1. Single Apps ( normal Rails or rack applications) 
    
CapistranoMulticonfigParallel recognizes only "development" and "webdev" as stages for development
if you use other stages for development, you need to configure it like this. This will override the default configuration.
You will need to require this file in your Capfile also.

```ruby
CapistranoMulticonfigParallel.configure do |c|
c.development_stages = ["development", "some_other_stage"]
end
```
### Deploying the application  to multiple sandboxes ( works only with development environments)

```shell
# <box_name>     - the name of a sandbox
#<development_stage> - the name of one of the stages you previously configured
#<task_name> - the capistrano task that you want to execute ( example: 'deploy' )

bundle exec multi_cap  <development_stage> <task_name>   BOX=<box_name>,<box_name> 

```

If a branch is specified using "BRANCH=name" it will deploy same branch to all sandboxes
If a branch is not specified, will ask for each of the sandboxes the name of the branch to deploy
The branch environment variable is then passed to the capistrano task

Also the script will ask if there are any other environment variables that user might want to pass to each of the sandboxes separately.

### Deploying the application  to multiple stages  ( Using the customized command "deploy_stages")
  

```shell

bundle exec multi_cap deploy_stages  STAGES=development, staging, production
```

If a branch is specified using "BRANCH=name" it will deploy same branch to all stages
If a branch is not specified, will ask for each of the stage the name of the branch to deploy
The branch environment variable is then passed to the capistrano process

Also the script will ask if there are any other environment variables that user might want to pass to each of the stages separately.



2. Multiple Apps ( like [Caphub][caphub]  ) 


Configuration for this types of application is more complicated

```ruby
CapistranoMulticonfigParallel.configure do |c|
c.development_stages = ['development', 'webdev']  
c.task_confirmation_active = true
 c.task_confirmations = ['deploy:symlink:release'] 
 c.track_dependencies = true
  c.application_dependencies = [
    { app: 'blog', priority: 1, dependencies: [] },
    { app: 'blog2', priority: 2, dependencies: ['blog'] },
    { app: 'blog3', priority: 3, dependencies: ['blog', 'blog2'] },
  ]
end
```

The "development_stages" options is used so that the gem can know if sandboxes are allowed for those environments.

The "task_confirmation_active" option can have only two values:
    - false  - all threads are executing normally without needing confirmation from user
   - true - means threads need confirmation from user ( Can we used to synchronize all processes to wait before executing a task) 
             For this we use the option "task_confirmations" which is a array with string. 
              Each string is  the name of the task that needs confirmation.


If you want to deploy an application with dependencies you can use   the option "track_dependencies".
If that options has value "true" , it will ask the user before deploying a application if he needs the dependencies deployed too

The dependencies are being kept in the option "application_dependencies"
This is an array of hashes. Each hash has only the keys "app" ( app name), "priority" and "dependencies" ( an array of app names that this app is dependent to)

 

 Testing
--------

To test, do the following:

1. cd to the gem root.
2. bundle install
3. bundle exec rake

Contributions
--------

Please log all feedback/issues via [Github Issues][issues].  Thanks.

[issues]: http://github.com/bogdanRada/capistrano_multiconfig_parallel/issues

Contributing to capistrano_multiconfig_parallel
--------

* Check out the latest master to make sure the feature hasn't been implemented or the bug hasn't been fixed yet.
* Check out the issue tracker to make sure someone already hasn't requested it and/or contributed it.
* Fork the project.
* Start a feature/bugfix branch.
* Commit and push until you are happy with your contribution.
* Make sure to add tests for it. This is important so I don't break it in a future version unintentionally.
* Please try not to mess with the Rakefile, version, or history. If you want to have your own version, or is otherwise necessary, that is fine, but please isolate to its own commit so I can cherry-pick around it.
* You can read more details about contributing in the [Contributing][contributing] document

[contributing]: https://github.com/bogdanRada/capistrano_multiconfig_parallel/blob/master/CONTRIBUTING.md

== Copyright

Copyright (c) 2015 bogdanRada. See LICENSE.txt for
further details.
