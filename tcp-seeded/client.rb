#!/usr/bin/env ruby

require 'socket'
require 'securerandom'

class TestClient
  def initialize(remote_host = '127.0.0.1', remote_port = 4242, seed = 42)
    @random      = Random.new(seed.to_i)
    @remote_host = remote_host
    @remote_port = remote_port
  end

  def run
    puts "Connecting to #{@remote_host} on port #{@remote_port} ..."
    @socket = TCPSocket.new(@remote_host, @remote_port)

    puts "Sending data ..."
    loop do
      @socket.syswrite(@random.bytes(8192))
    end
  end
end

TestClient.new(*ARGV).run
