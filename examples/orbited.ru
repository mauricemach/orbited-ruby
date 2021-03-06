require 'lib/csp'
module Orbited
  FrameOpen = 0
  FrameClose = 1
  FrameData = 2
  
  InvalidHandshake        = 102
  UserConnectionReset     = 103
  RemoteConnectionTimeout = 104
  Unauthorized            = 106
  RemoteConnectionFailed  = 108
  RemoteConnectionClosed  = 109
  ProtocolError           = 110
  
  class Outgoing < EventMachine::Connection
    def initialize(incoming, socket_id, host, port)
      @incoming, @socket_id, @host, @port = incoming, socket_id, host, port
      super
    end
    
    def post_init
      @incoming.new_outgoing(self)
    end
    
    def receive_data(data)
      @incoming.send_data(@socket_id, FrameData, data)
    end
    
    def unbind
      @incoming.unbind_socket(@socket_id, RemoteConnectionClosed)
    end
  end
  
  class Incoming < CSP::Session
    class FatalError < Exception; end
    
    def post_init()
      @buffer = ""
      @buffers = {}
      @sockets = {}
      @active = true
    end
    
    def active?; @active end
    
    def receive_data(data)
      @buffer << data
      return unless frame_begins_at_index = @buffer.index('[') # Start of a json encoded frame
      size = @buffer[0, frame_begins_at_index].to_i
      frame_ends_at_index = size + size.to_s.size
      frame = @buffer[0, frame_ends_at_index]
      @buffer = @buffer[frame_ends_at_index, @buffer.size - frame_ends_at_index]
      frame = JSON.parse(frame)
      socket_id, frame_type, data = *frame
      
      if @sockets[socket_id]
        process_frame(*frame)
      else
        handshake(socket_id, frame, data)
      end
    rescue JSON::ParserError
      Orbited.logger.error("Failed to parse frame: #{frame}")
      raise FatalError.new("Cannot Parse Frame")
    end
    
    def handshake(socket_id, frame_type, data)
      return @buffers[socket_id].append([socket_id, frame_type, data]) if @buffers[socket_id]
      return self.unbind_socket(socket_id, ProtocolError) unless frameType == FrameOpen
      
      host, port = *data
      return unbind_socket(socket_id, InvalidHandshake) if host.nil? or port.nil?
      
      alowed = Orbited.config[:access].find do |source|
        source == AnySource || source == @request.host
      end
      
      unless allowed
        Orbited.logger.warn("Unauthorized connect from #{@request.host}:#{@request.port} => #{host}:#{port}")
        unbind_socket(socket_id, Unauthorized)
        return
      end
     
      Orbited.logger.info("new connection from #{peer.host}:#{peer.port} => #{host}:#{port}"
      EventMachine.connect(host, port, Outgoing, self, socket_id, host, port)
      self.buffers[socketId] = []
    end
    
    def send_data(*raw_data)
      data = JSON.encode(raw_data)
      super("#{data.size}#{data}")
    end
    
    def new_outgoing(outgoing)
      socket_id = outgoing.socket_id
      @sockets[socket_id] = outgoing
      send_data(socket_id, FrameOpen)
      @buffers[socket_id] && @buffers[socket_id].each{|frame| process_frame(*frame) }
      @buffers.delete(socket_id)
    end
    
    def process_frame(socket_id, frame_type, data)
      case frame_type
      when FrameClose
        unbind_socket(socket_id, UserConnectionReset)
      when FrameData
        @sockets[socket_id].send_data(data)
      else
        unbind_socket(socket_id, ProtocolError)
      end
    end
    
    def unbind
      Orbited.logger.debug("connectionLost")
      @active = false 
      @buffer = ""
      @buffers = {}
      @sockets.each do |socket_id, socket|
        @sockets.delete(socket_id)
        socket.close_connection_after_writing        
      end
    end
    
    def unbind_socket(socket_id, reason)
      return unless active?
      @sockets[socket_id] @sockets[socket_id].lose_connection
      @sockets.delete(socket_id)
      @buffers.delete(socket_id)
      send_data(socketId, FRAME_CLOSE, reason)
    end
  end
end
