$LOAD_PATH.unshift File.join(__dir__, '../vendor/topology/lib')

require 'forwardable'
require 'optparse'
require 'path_manager'
require 'sliceable_switch'
require 'topology_controller'
require 'control_receiver'
require 'ip_address_manager'

# L2 routing switch
class RoutingSwitch < Trema::Controller
  extend Forwardable

  # Command-line options of RoutingSwitch
  class Options
    attr_reader :slicing

    def initialize(args)
      @opts = OptionParser.new
      @opts.on('-s', '--slicing') { @slicing = true }
      @opts.parse [__FILE__] + args
    end
  end

  timer_event :flood_lldp_frames, interval: 1.sec

  def_delegators :@topology, :flood_lldp_frames

  def slice
    fail 'Slicing is disabled.' unless @options.slicing
    Slice
  end

  # @!group Trema event handlers

  def start(args)
    @options = Options.new(args)
    @path_manager = start_path_manager
    @topology = start_topology args
    @ip_address_manager = IPAddressManager.new
    @control_receiver = ControlReceiver.new(@options)
    @control_receiver.vm_manager.add_ip_address_manager(@ip_address_manager)
    # 制御サーバ起動
    Thread.start(@control_receiver) do |cr|
      cr.start_server
    end
    # IPアドレス管理サーバ起動
    Thread.start(@ip_address_manager) do |iam|
      iam.start_manager
    end
    @control_receiver.add_observer(self)
    logger.info 'Routing Switch started.'
  end

  def_delegators :@topology, :switch_ready
  def_delegators :@topology, :features_reply
  def_delegators :@topology, :switch_disconnected
  def_delegators :@topology, :port_modify

  def packet_in(dpid, message)
    # for DHCP
    case message.data
    when Dhcp::Discover, Dhcp::Offer, Dhcp::Request, Dhcp::Ack
      send_packet_out(
        dpid,
        packet_in: message,
        actions: SendOutPort.new(:flood)
      )
    else
      @topology.packet_in(dpid, message)
      @path_manager.packet_in(dpid, message) unless message.lldp?
    end
  end

  private

  def start_path_manager
    fail unless @options
    (@options.slicing ? SliceableSwitch : PathManager).new.tap(&:start)
  end

  def start_topology(args)
    fail unless @path_manager
    TopologyController.new.tap do |topology_controller|
      args.delete_if{|arg| arg =~ /\-s|\-\-slicing/} if @options.slicing
      topology_controller.start args
      topology_controller.add_observer @path_manager
      slice.add_observer @path_manager if @options.slicing
      @path_manager.set_topology topology_controller.topology
      @path_manager.add_observer topology_controller.view
    end
  end

end
