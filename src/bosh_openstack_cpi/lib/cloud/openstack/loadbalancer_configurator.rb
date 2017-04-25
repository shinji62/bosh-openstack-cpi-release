module Bosh::OpenStackCloud
  class LoadbalancerConfigurator

    def initialize(network_spec, openstack)
      @network_spec = network_spec
      @openstack = openstack
    end

    def add_vm_to_pool(server, pool_spec)
      begin
        pool = LoadbalancerPool.new(pool_spec)
        openstack_pool_id = openstack_pool_id(pool.name)
        ip = NetworkConfigurator.gateway_ip(@network_spec, @openstack, server)
        subnet_id = matching_subnet_id(ip)

        @openstack.with_openstack {
          @openstack.network.create_lbaas_pool_member(openstack_pool_id, ip, pool.port, { subnet_id: subnet_id })
        }
      rescue Bosh::Clouds::VMCreationFailed => e
        message = "VM with id '#{server.id}' cannot be attached to load balancer pool '#{pool_spec['name']}'. Reason: #{e.message}"
        raise Bosh::Clouds::VMCreationFailed.new(false), message
      end
    end

    private

    def matching_subnet_id(ip)
      subnet_ids = NetworkConfigurator.matching_gateway_subnet_ids_for_ip(@network_spec, @openstack, ip)
      if subnet_ids.size > 1
        raise Bosh::Clouds::VMCreationFailed.new(false), "In network '#{NetworkConfigurator.get_gateway_network_id(@network_spec)}' more than one subnet CIDRs match the IP '#{ip}'"
      end
      if subnet_ids.empty?
        raise Bosh::Clouds::VMCreationFailed.new(false), "Network '#{NetworkConfigurator.get_gateway_network_id(@network_spec)}' does not contain any subnet to match the IP '#{ip}'"
      end
      subnet_ids.first
    end

    class LoadbalancerPool
      attr_reader :name, :port

      def initialize(pool)
        @name = pool['name']
        @port = pool['port']

        unless @name
          raise Bosh::Clouds::VMCreationFailed.new(false), 'Load balancer pool defined without a name'
        end

        unless @port
          raise Bosh::Clouds::VMCreationFailed.new(false), "Load balancer pool '#{@name}' has no port definition"
        end
      end
    end

    def openstack_pool_id(pool_name)
      pools = @openstack.with_openstack {
        @openstack.network.list_lbaas_pools({ 'name' => pool_name }).body['pools']
      }

      if pools.empty?
        raise Bosh::Clouds::VMCreationFailed.new(false), "Load balancer pool '#{pool_name}' does not exist"
      elsif pools.size > 1
        raise Bosh::Clouds::VMCreationFailed.new(false), "Load balancer pool '#{pool_name}' exists multiple times. Make sure to use unique naming."
      end
      pools.first['id']
    end
  end
end
