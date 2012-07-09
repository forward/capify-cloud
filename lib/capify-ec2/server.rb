require 'rubygems'
require 'fog/aws/models/compute/server'
require 'fog/brightbox/models/compute/server'

module Fog
  module Compute
    class AWS
      class Server
        def contact_point
          dns_name || public_ip_address || private_ip_address
        end
        
        def name
          tags["Name"]
        end
        
        def zone_id
          availability_zone
        end
      end
    end
    class Brightbox
      class Server
        def contact_point
          public_ip_address || private_ip_address
        end
        
        def tags
          {}
        end
      end
    end
  end
end
  