#!/usr/bin/env ruby

require 'socket'

class TestClient
  RETRIES = 5

  def initialize(remote_host = '127.0.0.1', remote_port = 4242, seed = 42)
    @random      = Random.new(seed.to_i)
    @remote_host = remote_host
    @remote_port = remote_port

    @socket = UDPSocket.new(Socket::PF_INET)
    @socket.setsockopt(Socket::IPPROTO_IP, Socket::IP_MTU_DISCOVER, Socket::IP_PMTUDISC_DO)
  end

  def run
    puts "Pinging #{@remote_host} on port #{@remote_port} ..."
    ping
    puts "Received pong from #{@remote_ip}."

    puts "Determining MTU ..."
    find_mtu

    puts "Starting test with MTU #{@mtu}."
    test
  end

  def ping
    loop do
      send('ping')
      sleep 1
      begin
        msg, addr = @socket.recvfrom_nonblock(10)
        if msg == 'pong'
          @remote_ip = addr[2]
          break
        end
      rescue Errno::EAGAIN
        # continue
      end
    end
  end

  def find_mtu
    range = 1..1500

    until range.count <= 2
      puts "Testing MTU between #{range.min} and #{range.max} ..."

      step_by = range.count / 10
      step_by = 1 if step_by < 1

      attempts = range.step(step_by).to_a
      attempts << range.max unless attempts.last == range.max

      send("mtu start #{range}")
      wait_for("mtu ready #{range}")

      failures = []
      attempts.each do |len|
        begin
          send('a' * len)
        rescue Errno::EMSGSIZE
          failures << len
        end
        sleep 0.05
      end

      send('mtu check')
      _, max = wait_for(/^mtu max (\d+)$/, 50)

      max_success = max.to_i
      failures += attempts.drop_while { |n| n <= max_success }
      min_failure = failures.min

      if min_failure == nil
        range = max_success..(max_success * 10)
      else
        range = max_success..min_failure
      end
    end

    send('mtu done')
    @mtu = range.min
  end

  def test
    send("start #{@mtu}")
    wait_for("go")

    seq = 0
    loop do
      seq += 1
      prefix = "data #{seq} "

      size = 30 + ((seq - 1) % (@mtu - 30))
      data = @random.bytes(size - prefix.length)

      (1..RETRIES).each do |i|
        send(prefix + data)
        ready, _ = IO.select([@socket], [], [], 1.0)
        break if ready

        puts "Timeout: no response for #{seq} (#{i}/#{RETRIES})."
        abort "Aborting due to timeout." if i == RETRIES
      end

      wait_for("ack #{seq}")
    end
  end

  def send(data)
    @socket.send(data, 0, @remote_ip || @remote_host, @remote_port)
  end

  def wait_for(expect, maxlen = expect.length + 10)
    loop do
      msg, addr = @socket.recvfrom(maxlen)
      _, port, ip = addr

      if ip != @remote_ip || port != @remote_port
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
end

TestClient.new(*ARGV).run
