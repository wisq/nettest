#!/usr/bin/env ruby

require 'socket'
require 'securerandom'

connect_to, control_port, data_port = ARGV
connect_to   ||= '127.0.0.1'
control_port ||= 4242
data_port    ||= control_port + 1

puts "Connecting to #{connect_to} on ports #{control_port} and #{data_port} ..."
control_sock = TCPSocket.new(connect_to, control_port)
data_sock    = TCPSocket.new(connect_to, data_port)

puts "Sending data ..."
loop do
  data = SecureRandom.random_bytes(8192)
  sum  = Digest::SHA1.hexdigest(data)
  data_sock.syswrite(data)
  control_sock.puts(sum)
end
