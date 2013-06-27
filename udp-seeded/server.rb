#!/usr/bin/env ruby

require 'socket'
require 'tempfile'
require 'highline/system_extensions'

class TestServer
  def initialize(listen_ip = '0.0.0.0', listen_port = 4242, seed = 42)
    @random = Random.new(seed.to_i)
    @socket = UDPSocket.new
    @socket.bind(listen_ip, listen_port)
  end

  def run
    puts "Waiting for ping ..."
    wait_ping

    puts "Waiting for MTU test ..."
    test_mtu
    puts "Done testing MTU."

    puts "Waiting for test start ..."
    test
  end

  private

  def send(data)
    @socket.send(data, 0, @remote_ip, @remote_port)
  end

  def wait_for(expect, maxlen = expect.length + 10)
    loop do
      msg, addr = @socket.recvfrom(maxlen)
      _, port, ip = addr

      if ip != @remote_ip || port.to_i != @remote_port
        puts "Unexpected message from #{ip} port #{port}."
        next
      end

      if expect === msg
        return [msg, $1, $2, $3]
      else
        puts "Unexpected message: #{msg.inspect}"
      end
    end
  end

  def wait_ping
    loop do
      msg, addr = @socket.recvfrom(10)
      _, port, ip = addr

      if msg == 'ping'
        @remote_ip   = ip
        @remote_port = port
        break
      else
        puts "Received unexpected message from #{ip} port #{port}."
      end
    end

    puts "Received ping from #{@remote_ip} port #{@remote_port}."
    send('pong')
  end

  def test_mtu
    loop do
      _, cmd, min, max = wait_for(/^mtu (done|start (\d+)\.\.(\d+))$/, 100)
      break if cmd == 'done'

      range = (min.to_i)..(max.to_i)
      puts "Client is testing MTUs between #{range.min} and #{range.max} ..."
      send("mtu ready #{range}")

      seen = []

      while msg = @socket.recv(range.max + 10)
        break if msg == 'mtu check'
        seen << msg.length
      end

      puts "MTUs seen: #{seen.sort.join(', ')}"
      send("mtu max #{seen.max}")
    end
  end

  def test
    _, maxlen = wait_for(/^start (\d+)$/, 50)
    maxlen = maxlen.to_i
    send("go")

    @passes = @fails = @total = 0
    @next_summary = Time.at(0)
    seen = -1
    loop do
      _, seq, actual = wait_for(/\Adata (\d+) (.*)\z/nm, maxlen + 10)
      seq = seq.to_i
      send("ack #{seq}")

      if seq <= seen
        puts "Duplicate packet: #{seq}"
        next
      end
      seen = seq

      expect = @random.bytes(actual.bytesize)
      check_data(seq, expect, actual)
      show_summary
    end
  end

  def show_summary
    if @next_summary < Time.now
      puts "Processed #{@total} packets.  #{@passes} passed, #{@fails} failed."
      @next_summary = Time.now + 1
    end
  end

  def check_data(seq, expect, actual)
    @total += 1

    if expect == actual
      @passes += 1
      return
    end

    @fails += 1
    width  = line_length(40) - 3
    output = []
    dump_binary(expect, width) do |expect_file|
      dump_binary(actual, width) do |actual_file|
        IO.popen(["diff", "-u", expect_file, actual_file]) do |fh|
          output = fh.readlines.drop(2) # remove header
        end
      end
    end

    width = output.map {|l| l.chomp.length}.max
    puts " ERROR in packet #{seq} ".center(width, '=')
    puts *output
    puts "=" * width
  end

  def line_length(min)
    width, height = HighLine::SystemExtensions.terminal_size
    [min, width].max
  end

  def dump_binary(data, width)
    offset_width = data.bytesize.to_s.length
    width   -= offset_width + 1  # reserve width for offset + space
    per_line = width / 9         # 8 bits + 1 space

    Tempfile.open("nettest") do |fh|
      line = []
      line_offset = 0

      data.bytes.each_with_index do |byte, offset|
        line << byte.to_s(2).rjust(8, '0')

        if line.count >= per_line
          fh.puts line_offset.to_s.rjust(offset_width) + " " + line.join(' ')
          line.clear
          line_offset = offset
        end
      end

      fh.close
      yield fh.path
    end
  end
end

TestServer.new(*ARGV).run
