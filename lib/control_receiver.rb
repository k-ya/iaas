require 'socket'
require 'json_api'
require 'vm_manager'
require 'host_manager'
require 'user_manager'
require 'settings'
require 'control_sender'

class ControlReceiver

  attr_reader :vm_manager

  def initialize(options)
    @vm_manager = VirtualMachineManager.new(options)
    @user_manager = UserManager.new(options)
    @host_manager = HostManager.new(options)
  end

  def start_server
    puts "start server"
    @socket = TCPServer.open(Settings::LISTENING_PORT)
    @continue = true
    while @continue
      control_json = ''
      tmp = @socket.accept

      while buf = tmp.gets
        control_json += buf.to_s
      end

      control = JSON.load(control_json)
      run(control)

      tmp.close
    end
  end

  def run(control)
    return unless control
    puts control['function']
    case control['function']
    when 'USER_CREATE'
      @user_manager.create(control['field'])
    when 'USER_DELETE'
      @user_manager.delete(control['field'])
    when 'VM_CREATE'
      @vm_manager.create(control['field'])
    when 'VM_MODIFY'
      @vm_manager.modify(control['field'])
    when 'VM_DELETE'
      @vm_manager.delete(control['field'])
    when 'VM_START'
      @vm_manager.start(control['field'])
    when 'VM_STOP'
      @vm_manager.stop(control['field'])
    when 'FW_CONTROL_ADD'

    when 'FW_CONTROL_MODIFY'
    when 'FW_CONTROL_DELETE'
    when 'VM_CREATE_ACK'
      @vm_manager.ack_for_create(control['field'])
    when 'VM_MODIFY_ACK'
      @vm_manager.ack_for_modify(control['field'])
    when 'VM_DELETE_ACK'
      @vm_manager.ack_for_delete(control['field'])
    when 'VM_START_ACK'
      @vm_manager.ack_for_start(control['field'])
    when 'VM_STOP_ACK'
      @vm_manager.ack_for_stop(control['field'])
    when 'USER_UPDATE'
      @user_manager.update(control['field'])
    when 'VM_STATUS_ACK'
      @user_manager.ack_for_update(control['field'])
    when 'HOST_UPDATE'
      @host_manager.update(control['field'])
    # error
    else
      puts 'unknown_function'
    end
  end

  def fw_control_add(field)
    return if field['allow']
    hash = {}
    hash['ether_type'] = 0x800
    hash['source_ip_address'] = field['source_ip_address'] if field['source_ip_address']
    hash['destination_ip_address'] = field['destination_ip_address'] if field['destination_ip_address']
    hash['ip_protocol'] = 6 if field['destination_tcp_port'] || field['source_tcp_port']
    hash['transport_source_port'] = field['source_tcp_port'] if field['source_tcp_port']
    hash['transport_destination_port'] = field['destination_tcp_port'] if field['destination_tcp_port']
    @fw_manager.add_block_entry(field['user_id'], 1000 - field['rule_no'].to_i, hash)
  end

  def fw_control_modify(field)
    return if field['allow']
    users = JsonAPI.file_reader(Settings::USERS_FILEPATH)
    search_line = ['users','user_id',field['user_id'],'fw_rule','rule_no',field['rule_no']]
    fw_rule = JsonAPI.search(users, search_line)

    hash = {}
    hash['ether_type'] = 0x800
    hash['source_ip_address'] = fw_rule['source_ip_address'] if fw_rule['source_ip_address']
    hash['destination_ip_address'] = fw_rule['destination_ip_address'] if fw_rule['destination_ip_address']
    hash['ip_protocol'] = 6 if fw_rule['destination_tcp_port'] || fw_rule['source_tcp_port']
    hash['transport_source_port'] = fw_rule['source_tcp_port'] if fw_rule['source_tcp_port']
    hash['transport_destination_port'] = fw_rule['destination_tcp_port'] if fw_rule['destination_tcp_port']
    @fw_manager.delete_firewall_entry(fw_rule['user_id'], 1000 - fw_rule['rule_no'].to_i, hash)

    hash = {}
    hash['ether_type'] = 0x800
    hash['source_ip_address'] = field['source_ip_address'] if field['source_ip_address']
    hash['destination_ip_address'] = field['destination_ip_address'] if field['destination_ip_address']
    hash['ip_protocol'] = 6 if field['destination_tcp_port'] || field['source_tcp_port']
    hash['transport_source_port'] = field['source_tcp_port'] if field['source_tcp_port']
    hash['transport_destination_port'] = field['destination_tcp_port'] if field['destination_tcp_port']
    @fw_manager.add_block_entry(field['user_id'], 1000 - field['rule_no'].to_i, hash)
  end

  def fw_control_delete(field)
    users = JsonAPI.file_reader(Settings::USERS_FILEPATH)
    search_line = ['users','user_id',field['user_id'],'fw_rule','rule_no',field['rule_no']]
    fw_rule = JsonAPI.search(users, search_line)

    hash = {}
    hash['ether_type'] = 0x800
    hash['source_ip_address'] = fw_rule['source_ip_address'] if fw_rule['source_ip_address']
    hash['destination_ip_address'] = fw_rule['destination_ip_address'] if fw_rule['destination_ip_address']
    hash['ip_protocol'] = 6 if fw_rule['destination_tcp_port'] || fw_rule['source_tcp_port']
    hash['transport_source_port'] = fw_rule['source_tcp_port'] if fw_rule['source_tcp_port']
    hash['transport_destination_port'] = fw_rule['destination_tcp_port'] if fw_rule['destination_tcp_port']
    @fw_manager.delete_firewall_entry(fw_rule['user_id'], 1000 - fw_rule['rule_no'].to_i, hash)
  end

  def add_fw_manager(controller)
    @fw_manager = controller
  end

  def end_server
    @continue = false
    @socket.close
  end

end
