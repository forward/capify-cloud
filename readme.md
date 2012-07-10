Capify Cloud
====================================================

capify-cloud is used to generate capistrano namespaces using ec2 tags and a hack with Brightbox server-groups to emulate tags.
Tags are simulated on Brightbox using a server_group containing a ":" (e.g. Roles:web)

eg: If you have 2 servers on amazon's ec2 and a DB server at Brightbox

    server-1 Tag: Roles => "web", Options => "cron,resque, db"
    server-2 Server-Group: Roles:db
    server-3 Tag: Roles => "web,db, app"

Installing

    gem install capify-cloud

In your deploy.rb:

```ruby
require "capify-cloud/capistrano"
cloud_roles :web
```

Will generate

```ruby
task :server-1 do
  role :web, {server-1 public dns fetched from Amazon}, :cron=>true, :resque=>true
end

task :server-3 do
  role :web, {server-1 public dns fetched from Amazon}
end

task :web do
  role :web, {server-1 public dns fetched from Amazon}, :cron=>true, :resque=>true
  role :web, {server-3 public dns fetched from Amazon}
end
```

Additionally

```ruby
require "capify-cloud/capistrano"
cloud_roles :db
```

Will generate

```ruby
task :server-2 do
  role :db, {server-2 public or private IP, fetched from Brightbox}
end

task :server-3 do
  role :db, {server-3 public dns fetched from Amazon}
end

task :db do
  role :db, {server-2 public or private IP, fetched from Brightbox}
  role :db, {server-3 public dns fetched from Amazon}
end
```

Running

```ruby
cap web cloud:date
```

will run the date command on all server's tagged with the web role

Running

```ruby
cap server-1 cloud:register_instance -s loadbalancer=elb-1
```

will register server-1 to be used by elb-1

Running

```ruby
cap server-1 cloud:deregister_instance
```

will remove server-1 from whatever instance it is currently
registered against.

Running

```ruby
cap cloud:status
```

will list the currently running servers and their associated details
(public dns, instance id, roles etc)

Running

```ruby
cap cloud:ssh #
```

will launch ssh using the user and port specified in your configuration.
The # argument is the index of the server to ssh into. Use the 'cloud:status'
command to see the list of servers with their indices.

More options
====================================================

In addition to specifying options (e.g. 'cron') at the server level, it is also possible to specify it at the project level.
Use with caution! This does not work with autoscaling.

```ruby
cloud_roles {:name=>"web", :options=>{:cron=>"server-1"}}
```

Will generate

```ruby
task :server-1 do
  role :web, {server-1 public dns fetched from Amazon}, :cron=>true
end

task :server-3 do
  role :web, {server-1 public dns fetched from Amazon}
end

task :web do
  role :web, {server-1 public dns fetched from Amazon}, :cron=>true
  role :web, {server-3 public dns fetched from Amazon}
end
```

Which is cool if you want a task like this in deploy.rb

```ruby
task :update_cron => :web, :only=>{:cron} do
  Do something to a server with cron on it
end

cloud_roles :name=>:web, :options=>{ :default => true }
```

Will make :web the default role so you can just type 'cap deploy'.
Multiple roles can be defaults so:

```ruby
cloud_roles :name=>:web, :options=>{ :default => true }
cloud_roles :name=>:app, :options=>{ :default => true }
```

would be the equivalent of 'cap app web deploy'

Cloud config
====================================================

This gem requires 'config/cloud.yml' in your project.
The yml file needs to look something like this:
  
```ruby
:cloud_providers: ['AWS', 'Brightbox']

:AWS:
  :aws_access_key_id: "YOUR ACCESS KEY"
  :aws_secret_access_key: "YOUR SECRET"
  :params:
    :region: 'eu-west-1'
  :load_balanced: true
  :project_tag: "YOUR APP NAME"
  
:Brightbox:
  :brightbox_client_id: "YOUR CLIENT ID"
  :brightbox_secret: "YOUR SECRET"
```
aws_access_key_id, aws_secret_access_key, and region are required for AWS. Other settings are optional.
brightbox_client_id and brightbox_secret: are required for Brightbox.
If you do not specify a cloud_provider, AWS is assumed.

If :load_balanced is set to true, the gem uses pre and post-deploy
hooks to deregister the instance, reregister it, and validate its
health.
:load_balanced only works for individual instances, not for roles.

The :project_tag parameter is optional. It will limit any commands to
running against those instances with a "Project" tag set to the value
"YOUR APP NAME".

## Development

Source hosted at [GitHub](http://github.com/ncantor/capify-cloud).
Report Issues/Feature requests on [GitHub Issues](http://github.com/ncantor/capify-cloud/issues).

### Note on Patches/Pull Requests

 * Fork the project.
 * Make your feature addition or bug fix.
 * Add tests for it. This is important so I don't break it in a
   future version unintentionally.
 * Commit, do not mess with rakefile, version, or history.
   (if you want to have your own version, that is fine but bump version in a commit by itself I can ignore when I pull)
 * Send me a pull request. Bonus points for topic branches.

## Copyright

Original version: Copyright (c) 2012 Forward. See [LICENSE](https://github.com/ncantor/capify-cloud/blob/master/LICENSE) for details.
