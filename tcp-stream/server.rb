#!/usr/bin/env ruby

require 'socket'
require 'digest'

listen_on, control_port, data_port = ARGV
listen_on    ||= '0.0.0.0'
control_port ||= 4242
data_port    ||= control_port + 1

control_server = TCPServer.new(listen_on, control_port)
data_server    = TCPServer.new(listen_on, data_port)

puts "Waiting for control connection ..."
control_sock = control_server.accept
control_server.close

puts "Waiting for data connection ..."
data_sock    = data_server.accept
data_server.close

puts "Receiving data ..."

new_line = true
loop do
  data     = data_sock.read(8192)
  expected = control_sock.readline.chomp
  actual   = Digest::SHA1.hexdigest(data)

  if expected == actual
    print "."
    new_line = false
    $stdout.flush
  else
    puts unless new_line
    puts "FAILED: #{expected} vs #{actual}"
    new_line = true
  end
end
