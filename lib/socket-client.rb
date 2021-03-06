require 'socket'
require 'openssl'

require_relative 'events'

class SocketClient

  def initialize e
    @e = e
    @debug = true
    @sockets = []
  end

  def Create name, host, port, ssl
    sock = TCPSocket.open(host, port)
    sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, true)

    if ssl
      ssl_context = OpenSSL::SSL::SSLContext.new
      ssl_context.verify_mode = OpenSSL::SSL::VERIFY_NONE
      sock = OpenSSL::SSL::SSLSocket.new(sock, ssl_context)
      sock.sync = true
      sock.connect
    end

    if sock
      hash = {"name" => name, "host" => host, "port" => port, "ssl" => ssl, "socket" => sock}
      @sockets = [] if @sockets.nil?
      @sockets.push(hash)
      @e.Run "ConnectionCompleted", name, sock
    end
  end

  def CheckForNewData
    if !@sockets.nil?
      @sockets.each { |hash|
        name = hash["name"]
        ssl  = hash["ssl"]
        sock = hash["socket"]

        begin
          # This is an IRC specific thing and *not* RPS.
          # This will be fixed at some point.
          data = sock.gets("\r\n") if ssl
          data = sock.gets("\r\n") if !ssl
        rescue IO::WaitReadable

        end

        if data.is_a?(String)
          dataline = data.split("\r\n")
          dataline.each { |line|
            line = line.to_s.chomp
            time = Time.now
            puts "[~R] [#{name}] [#{time.strftime("%Y-%m-%d %H:%M:%S")}] #{line}" if @debug
            @e.Run "NewData", name, sock, line
          }
        end

        data = nil
        line = nil
        dataline = nil
      }
    end

  end

  def Get name
    @sockets.each { |socket| return socket["sock"] if socket["name"] == name }
    return false
  end

end # End Class "SocketClient"
