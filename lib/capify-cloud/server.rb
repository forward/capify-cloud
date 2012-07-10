require 'rubygems'
require 'fog/aws/models/compute/server'
require 'fog/brightbox/models/compute/server'

module Fog
  module Compute
    class AWS
      class Server
        def contact_point
          public_ip_address || private_ip_address
        end
        
        def name
          tags["Name"]
        end
        
        def zone_id
          availability_zone
        end
        
        def provider
          'AWS'
        end
      end
    end
    class Brightbox
      class Server
        def contact_point
          public_ip_address || private_ip_address
        end
        
        def tags
          tags = server_groups.map {|server_group| server_group["name"]}.select{|tag| tag.include?(":")}
          tags_hash = tags.inject({}) do |map, individual|
            key, value = individual.split(":")
            map[key] = value
            map
          end
          tags_hash
        end
        
        def provider
          'Brightbox'
        end
      end
    end
  end
end
  