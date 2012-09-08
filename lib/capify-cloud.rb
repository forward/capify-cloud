require 'rubygems'
require 'fog'
require 'colored'
require File.expand_path(File.dirname(__FILE__) + '/capify-cloud/server')


class CapifyCloud

  attr_accessor :load_balancers, :instances, :lb_instances, :deregister_lb_instances
  SLEEP_COUNT = 5
  
  def initialize(cloud_config = "config/cloud.yml")
    
    case cloud_config
    when Hash
      @cloud_config = cloud_config
    when String
      @cloud_config = YAML.load_file cloud_config
    else
      raise ArgumentError, "Invalid cloud_config: #{cloud_config.inspect}"
    end

    @cloud_providers = @cloud_config[:cloud_providers]
    
    @load_balancers = elb.load_balancers
    @instances = []
    @lb_instances = {}
    @deregister_lb_instances = {}

    @cloud_providers.each do |cloud_provider|
      config = @cloud_config[cloud_provider.to_sym]
      case cloud_provider
      when 'Brightbox'
        servers = Fog::Compute.new(:provider => cloud_provider, :brightbox_client_id => config[:brightbox_client_id],
          :brightbox_secret => config[:brightbox_secret]).servers
        servers.each do |server|
          @instances << server if server.ready?
        end
      else
        regions = determine_regions(cloud_provider)
        regions.each do |region|
          servers = Fog::Compute.new(:provider => cloud_provider, :aws_access_key_id => config[:aws_access_key_id], 
            :aws_secret_access_key => config[:aws_secret_access_key], :region => region).servers
          servers.each do |server|
            @instances << server if server.ready?
          end
        end
      end
    end
  end 
  
  def determine_regions(cloud_provider = 'AWS')
    @cloud_config[cloud_provider.to_sym][:params][:regions] || [@cloud_config[cloud_provider.to_sym][:params][:region]]
  end
    
  def display_instances
    desired_instances.each_with_index do |instance, i|
      puts sprintf "%02d:  %-40s  %-20s %-20s  %-20s  %-25s  %-20s  (%s)  (%s)",
        i, (instance.name || "").green, instance.provider.yellow, instance.id.red, instance.flavor_id.cyan,
        instance.contact_point.blue, instance.zone_id.magenta, (instance.tags["Roles"] || "").yellow,
        (instance.tags["Options"] || "").yellow
      end
  end

  def server_names
    desired_instances.map {|instance| instance.name}
  end
    
  def project_instances
    @instances.select {|instance| instance.tags["Project"] == @cloud_config[:project_tag]}
  end
  
  def desired_instances
    @cloud_config[:project_tag].nil? ? @instances : project_instances
  end
 
  def get_instances_by_role(role)
    desired_instances.select {|instance| instance.tags['Roles'].split(%r{,\s*}).include?(role.to_s) rescue false}
  end
  
  def get_instances_by_region(roles, region)
    return unless region
    desired_instances.select {|instance| instance.availability_zone.match(region) && instance.roles == roles.to_s rescue false}
  end 
  
  def get_instance_by_name(name)
    desired_instances.select {|instance| instance.name == name}.first
  end
    
  def instance_health(load_balancer, instance)
    elb.describe_instance_health(load_balancer.id, instance.id).body['DescribeInstanceHealthResult']['InstanceStates'][0]['State']
  end
    
  def elb
    @elb ||= Fog::AWS::ELB.new(:aws_access_key_id => @cloud_config[:AWS][:aws_access_key_id], :aws_secret_access_key => @cloud_config[:AWS][:aws_secret_access_key], :region => @cloud_config[:AWS][:params][:region])
  end

  def loadbalancer (roles, named_load_balancer, *args)
    role = args[0]
    deregister_arg = args[1][:deregister] rescue false
    require_arglist = args[1][:require] rescue {}
    exclude_arglist = args[1][:exclude] rescue {}

    # get the named load balancer
    named_elb = get_load_balancer_by_name(named_load_balancer.to_s)

    # must exit if no load balancer on record for this account by given name 
    raise Exception, "No load balancer found named: #{named_load_balancer.to_s}" if named_elb.nil?

    @lb_instances[named_elb] = @instances.clone

    # keep only instances belonging to this role
    ips = roles[role].servers.map{|s| Socket.getaddrinfo(s.to_s, nil)[0][2]}
    @lb_instances[named_elb].delete_if { |i|  !ips.include?(i.contact_point) }

    # reduce against 'require' args, if an instance doesnt have the args in require_arglist, remove
    @lb_instances[named_elb].delete_if { |i| ! all_args_within_instance(i, require_arglist) }  unless require_arglist.nil? or require_arglist.empty?

    # reduce against 'exclude_arglist', if an instance has any of the args in exclude_arglist, remove
    @lb_instances[named_elb].delete_if { |i|   any_args_within_instance(i, exclude_arglist) }  unless exclude_arglist.nil? or exclude_arglist.empty?

    @lb_instances[named_elb].compact! if @lb_instances[named_elb]

    # Save instances for deregistration hook
    @deregister_lb_instances[named_elb] ||= []
    @deregister_lb_instances[named_elb] += @lb_instances[named_elb] if deregister_arg
  end

  def any_args_within_instance(instance, exclude_arglist)
    exargs = exclude_arglist.clone # must copy since delete transcends scope; if we don't copy, subsequent 'map'ped enum arglists would be side-effected
    tag_exclude_state = nil # default assumption
    # pop off a :tags arg to treat separately, its a separate namespace
    tag_exclude_arglist = exargs.delete(:tags)

    tag_exclude_state = tag_exclude_arglist.map { |k, v| (instance.tags[k] == v rescue nil) }.inject(nil) { |inj, el| el || inj } if !tag_exclude_arglist.nil?
    # we want all nils for the result here, so we logical-or the result map, and invert it
    tag_exclude_state || exargs.map { |k, v| instance.send(k) == v }.inject(nil) { |inj, el| inj || el }
  end

  # the instance has attributes
  def all_args_within_instance(instance, require_arglist)
    reqargs = require_arglist.clone # must copy since delete transcends scope; if we don't copy, subsequent 'map'ped enum arglists would be side-effected
    tag_require_state = true # default assumption
    # pop off a :tags arg to treat separately, effectively  a separate namespace to be checked agains
    tag_require_arglist = reqargs.delete(:tags)
    tag_require_state = tag_require_arglist.map { |k, v| (instance.tags[k] == v rescue nil) }.inject(nil) { |inj, el| el || inj } if !tag_require_arglist.nil?

    # require arglist is a hash with k/v's, each of those need to be in the instance
    tag_require_state && reqargs.map { |k, v| instance.send(k) == v }.inject(true) { |inj, el| inj && el }
  end
  
  def get_load_balancers_by_instance(instance_id)
    hash = @load_balancers.inject({}) do |collect, load_balancer|
      collect ||= {}
      load_balancer.instances.each {|load_balancer_instance_id| collect[load_balancer_instance_id] ||= []; collect[load_balancer_instance_id] << load_balancer}
      collect
    end

    hash[instance_id] || []
  end
  
  def get_load_balancer_by_name(load_balancer_name)
    lbs = {}
    @load_balancers.each do |load_balancer|
      lbs[load_balancer.id] = load_balancer
    end
    lbs[load_balancer_name.to_s]
  end

  def register_instance_in_elb(instance, load_balancer)
      puts "\tREGISTER: #{instance.name}@#{load_balancer.id}"
      elb.register_instances_with_load_balancer(instance.id, load_balancer.id)

      fail_after = @cloud_config[:fail_after] || 30
      state = instance_health(load_balancer, instance)
      time_elapsed = 0
      
      while time_elapsed < fail_after
        break if state == "InService"
        sleep SLEEP_COUNT
        time_elapsed += SLEEP_COUNT
        puts "\tVerifying Instance Health: #{instance.name}@#{load_balancer.id}"
        state = instance_health(load_balancer, instance)
      end
      if state == 'InService'
        puts "\t#{instance.name}@#{load_balancer.id}: Healthy"
      else
        puts "\t#{instance.name}@#{load_balancer.id}: tests timed out after #{time_elapsed} seconds."
      end
  end

  def deregister_instance_from_elb(instance, load_balancer)
    puts "\tDEREGISTER: #{instance.name}@#{load_balancer.id}"
    elb.deregister_instances_from_load_balancer(instance.id, load_balancer.id)
  end

  def deregister_instance_from_elbs(instance)
    load_balancers = get_load_balancers_by_instance(instance.id)
    return if load_balancers.empty?
    load_balancers.each do |load_balancer|
      deregister_instance_from_elb(instance, load_balancer)
    end
  end

  def register_instances_in_elb_hook
    @lb_instances.each do |load_balancer, instances| 
      instances.each do |instance|
        register_instance_in_elb(instance, load_balancer)
      end
    end
  end

  def deregister_instances_from_elb_hook
    @deregister_lb_instances.each do |load_balancer, instances| 
      instances.each do |instance|
        deregister_instance_from_elb(instance, load_balancer)
      end
    end
  end

  def deregister_instance_from_elbs_hook(instance_name)
    instance = get_instance_by_name(instance_name)
    return if instance.nil?
    deregister_instance_from_elbs(instance)
  end
  
  def register_instance_in_elb_hook(instance_name, load_balancer_name)
    instance = get_instance_by_name(instance_name)
    return if instance.nil?
    load_balancer = get_load_balancer_by_name(load_balancer_name)
    return if load_balancer.nil?
    register_instance_in_elb(instance, load_balancer)
  end
end
