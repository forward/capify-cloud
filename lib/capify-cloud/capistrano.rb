require File.join(File.dirname(__FILE__), '../capify-cloud')
require 'colored'

Capistrano::Configuration.instance(:must_exist).load do
  def capify_cloud
    @capify_cloud ||= CapifyCloud.new(fetch(:cloud_config, 'config/cloud.yml'))
  end

  namespace :cloud do

    desc "Prints out all cloud instances. index, name, instance_id, size, DNS/IP, region, tags"
    task :status do
      capify_cloud.display_instances
    end

    desc "Deregisters instance from its ELB"
    task :deregister_instance do
      instance_name = variables[:logger].instance_variable_get("@options")[:actions].first
      capify_cloud.deregister_instance_from_elb(instance_name)
    end

    desc "Registers an instance with an ELB."
    task :register_instance do
      instance_name = variables[:logger].instance_variable_get("@options")[:actions].first
      load_balancer_name = variables[:logger].instance_variable_get("@options")[:vars][:loadbalancer]
      capify_cloud.register_instance_in_elb(instance_name, load_balancer_name)
    end

    task :date do
      run "date"
    end

    desc "Prints list of cloud server names"
    task :server_names do
      puts capify_cloud.server_names.sort
    end

    desc "Allows ssh to instance by id. cap ssh <INSTANCE NAME>"
    task :ssh do
      server = variables[:logger].instance_variable_get("@options")[:actions][1]
      instance = numeric?(server) ? capify_cloud.desired_instances[server.to_i] : capify_cloud.get_instance_by_name(server)
      port = ssh_options[:port] || 22
      command = "ssh -p #{port} #{user}@#{instance.contact_point}"
      puts "Running `#{command}`"
      exec(command)
    end
  end

  namespace :deploy do
    before "deploy", "cloud:deregister_instance"
    after "deploy", "cloud:register_instance"
    after "deploy:rollback", "cloud:register_instance"
  end

  def cloud_roles(*roles)
    logger_options = variables[:logger].instance_variable_get("@options")[:actions] || [] #Guard for :actions being nil, to work with sprinkle gem
    server_name = logger_options.first unless logger_options[1].nil?

    if !server_name.nil?
      named_instance = capify_cloud.get_instance_by_name(server_name)

      task named_instance.name.to_sym do
        remove_default_roles
        server_address = named_instance.contact_point
        named_instance.roles.each do |role|
          define_role({:name => role, :options => {:on_no_matching_servers => :continue}}, named_instance)
        end
      end unless named_instance.nil?
    end
    roles.each {|role| cloud_role(role)}
  end

  def cloud_role(role_name_or_hash)
    role = role_name_or_hash.is_a?(Hash) ? role_name_or_hash : {:name => role_name_or_hash,:options => {}}
    @roles[role[:name]]

    instances = capify_cloud.get_instances_by_role(role[:name])
    if role[:options].delete(:default)
      instances.each do |instance|
        define_role(role, instance)
      end
    end
    regions = capify_cloud.determine_regions
    regions.each do |region|
      define_regions(region, role)
    end unless regions.nil?

    define_role_roles(role, instances)
    define_instance_roles(role, instances)

  end

  def define_regions(region, role)
    instances = []
    @roles.each do |role_name, junk|
      region_instances = capify_cloud.get_instances_by_region(role_name, region)
      region_instances.each {|instance| instances << instance} unless region_instances.nil?
    end
    task region.to_sym do
      remove_default_roles
      instances.each do |instance|
        define_role(role, instance)
      end
    end
  end

  def define_instance_roles(role, instances)
    instances.each do |instance|
      task instance.name.to_sym do
        remove_default_roles
        define_role(role, instance)
      end
    end
  end

  def define_role_roles(role, instances)
    task role[:name].to_sym do
      remove_default_roles
      instances.each do |instance|
        define_role(role, instance)
      end
    end
  end

  def define_role(role, instance)
    options = role[:options]
    new_options = {}
    options.each {|key, value| new_options[key] = true if value.to_s == instance.name}
    instance.tags["Options"].split(%r{,\s*}).each { |option| new_options[option.to_sym] = true} rescue false

    if new_options
      role role[:name].to_sym, instance.contact_point, new_options
    else
      role role[:name].to_sym, instance.contact_point
    end
  end

  def numeric?(object)
    true if Float(object) rescue false
  end

  def remove_default_roles
    roles.reject! { true }
  end


end
