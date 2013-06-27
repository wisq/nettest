#!/usr/bin/env ruby

require 'socket'
require 'tempfile'
require 'highline/system_extensions'

class TestServer
  def initialize(listen_ip = '0.0.0.0', listen_port = 4242, seed = 42)
    @random = Random.new(seed.to_i)
    @server = TCPServer.new(listen_ip, listen_port)
  end

  def run
    puts "Waiting for connection ..."
    wait_for_connection

    puts "Receiving data ..."
    process_data
  end

  private

  def wait_for_connection
    @socket = @server.accept
    @server.close
  end

  def process_data
    chunk = 0
    @passes = @fails = @total = 0
    @next_summary = Time.at(0)

    loop do
      chunk += 1
      expect = @random.bytes(8192)
      actual = @socket.read(8192)
      raise "Short read" if actual.bytesize < 8192

      check_data(chunk, expect, actual)
      show_summary
    end
  end

  def show_summary
    if @next_summary < Time.now
      puts "Processed #{@total} chunks.  #{@passes} passed, #{@fails} failed."
      @next_summary = Time.now + 1
    end
  end

  def check_data(chunk, expect, actual)
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
    puts " ERROR in chunk #{chunk} ".center(width, '=')
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

      fh.puts line_offset.to_s.rjust(offset_width) + " " + line.join(' ')
      fh.close
      yield fh.path
    end
  end
end

TestServer.new(*ARGV).run
