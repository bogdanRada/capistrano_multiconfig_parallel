# Contributing

We love pull requests. Here's a quick guide.

Check out the latest master to make sure the feature hasn't been implemented or the bug hasn't been fixed yet.

Check out the issue tracker to make sure someone already hasn't requested it and/or contributed it.

Fork, then clone the repo:

    git clone git@github.com:your-username/capistrano_multiconfig_parallel.git

Start a feature/bugfix branch.

Set up your machine:

    bundle install

Make sure the tests pass:

    bundle exec rake

Make your change. Add tests for your change. Make the tests pass:

    bundle exec rake

Push to your fork and [submit a pull request][pr].

[pr]: https://github.com/bogdanRada/capistrano_multiconfig_parallel/compare

At this point you're waiting on us. We like to at least comment on pull requests
within three business days (and, typically, one business day). We may suggest
some changes or improvements or alternatives.

Some things that will increase the chance that your pull request is accepted:

* Write tests.
* Try to follow this [style guide][style].
* Write a [good commit message][commit].

[style]: https://github.com/thoughtbot/guides/tree/master/style
[commit]: http://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html

Please try not to mess with the Rakefile, version, or history. If you want to have your own version, or is otherwise necessary, that is fine, but please isolate to its own commit so I can cherry-pick around it.
