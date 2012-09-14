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

You also can use  `:require` and `:exclude` parameters:

 ```ruby
cloud_roles :name=>:web, :options=>{ :default => true }, :require => { :state => "running",  :tags => {'new' => "yes"}}
cloud_roles :name=>:app, :exclude => { :instance_type => "t1.micro", :tags => {'new' => "no"}  }
```

See `Load balancing (AWS)` below for more details.

Load balancing (AWS)
====================================================

`loadbalancer` configuration allow you to automatically register instances to specified load balancer. There's post-deploy hook `cloud:register_instances` which will register your instances after deploy.
In order to define your instance sets associated with your load balancer, you must specify the load balancer name, the associated roles for that load balancer and any optional params:
For example, in deploy.rb, you would enter the load balancer name (e.g. 'lb_webserver'), the capistrano role associated with that load balancer (.e.g. 'web'),
and any optional params.

```ruby
loadbalancer :lb_webserver, :web
loadbalancer :lb_appserver, :app
loadbalancer :lb_dbserver, :db, :port => 22000
```

There are three special optional parameters you can add, `:require`, `:exclude` and `:deregister` . These allow you to register instances associated with your named load balancer, if they meet or fail to meet your `:require`/`:exclude` specifications. If `:deregister` is set to true, the gem uses pre-deploy hook "cloud:deregister_instances" to deregister the instances before deploy.

The :require and :exclude parameters work on Amazon EC2 instance metadata.

AWS instances have top level metadata and user defined tag data, and this data can be used by your loadbalancer rule
 to include or exclude certain instances from the instance set.

Take the :require keyword; Lets say  we only want to register AWS instances which are in the 'running' state. To do that:

```ruby
loadbalancer :lb_appserver, :app, :require => { :state => "running" }
```

Perhaps you have added tags to your instances, if so, you might want to register only the instances meeting a specific tag value:

```ruby
loadbalancer :lb_appserver, :app, :require => { :state => "running", :tags => {'fleet_color' => "green", 'tier' => 'free'} }
```

Or if you want deregister instances for role :app and specific tag during deployment:

```ruby
loadbalancer :lb_appserver, :app, :deregister => true, :require => { :tags => {'master' => 'true'} }
```

Now consider the :exclude keyword; Lets say we want to exclude from load balancer AWS instances which are 'micro' sized. To do that:
  
```ruby
loadbalancer :lb_appserver, :app, :exclude => { :instance_type => "t1.micro"  }
```

You can exclude instances that have certain tags:

```ruby
loadbalancer :lb_appserver, :app, :exclude => { :instance_type => "t1.micro", :tags => {'state' => 'dontdeploy' }  }
```

NOTE: `:exclude` won't deregester instances manually registered or registered during previous deployments

Some code ported from [cap-elb](https://github.com/danmiley/cap-elb)

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
  :project_tag: "YOUR APP NAME"
  
:Brightbox:
  :brightbox_client_id: "YOUR CLIENT ID"
  :brightbox_secret: "YOUR SECRET"
```
aws_access_key_id, aws_secret_access_key, and region are required for AWS. Other settings are optional.
brightbox_client_id and brightbox_secret: are required for Brightbox.
If you do not specify a cloud_provider, AWS is assumed.

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
