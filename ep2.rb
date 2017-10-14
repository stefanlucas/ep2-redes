require 'socket'
require 'ipaddr'
require 'thread'

Thread.abort_on_exception=true
class Peer
  def initialize(port, number = nil)
    @server = TCPServer.open(port)
    @port = port
    @number = number
    @prime = false
    @interval = Hash.new
    @interval_queue = Array.new
    @remaining_interval = Hash.new
    @peers = Hash.new
    @id = nil
    @quantum = 10000000
    @leader = false
    @leader_id = nil

    @mutex = Mutex.new
    @peer_mutex = Mutex.new

    Socket.ip_address_list.each do |addr_info|
      if (addr_info.ip_address =~ /192.168.1.*/) == 0
        @id = addr_info.ip_address
      end 
    end
    if @id == nil
      puts "Erro, deveria existir uma interface lan com ip 192.168.1.*"
      exit(1)
    end
    if number != nil
      @leader = true
      @leader_id = @id
        if number.abs == 2 
          puts "É primo"
          exit(0)
        elsif number.abs == 1 || number.abs == 0
          puts "Não é primo"
          exit(0)
        end 

        if @quantum > (number.abs - 1)
          high = number.abs - 1
        else
          high = @quantum
        end

        @interval = {low: 2, high: high}
        @remaining_interval = {low: high + 1, high: number.abs - 1}
      else 
      @leader = false
      connect_peers
    end

    run
  end

  def run
    primality_test
    loop {
      handle(@server.accept) 
    }
  end

  def handle(socket)
    Thread.new {
      message = socket.gets
      puts "Peer " + socket.peeraddr[3].to_s + " request: " + message
      message = message.split(/[ \r\n]/)
      # caso em que é a primeira vez que o peer se conecta
      if @peers[socket.peeraddr[3]] == nil  
        puts "He just connected to the network"
        @mutex.synchronize {
          @peers[socket.peeraddr[3]] = Hash.new
          @peers[socket.peeraddr[3]][:status] = "connected"
        }
      # caso a conexão do peer tenha caido anteriormente
      elsif @peers[socket.peeraddr[3]][:status] == "lost"        
          puts socket.peeraddr[3] + "reconnected to the network"
        @mutex.synchronize {
          @peers[socket.peeraddr[3]][:status] = "reconnected"
        }
      end
      case message[0]
        when "leader?"
          if @leader
            response = "yes"
          else
            response = "no"
          end
        when "get_computation_info"
          response = @number.to_s + " " + @remaining_interval[:low].to_s + "," + @remaining_interval[:high].to_s
          @interval_queue.each do |interval|
            response += " " + interval[:low].to_s + "," + interval[:high].to_s
          end
        when "new_interval"
          @mutex.synchronize {
          #se o peer realmente terminou o trabalho ou é a primeira vez que ele se conecta
          if @peers[socket.peeraddr[3]][:low] == false || @peers[socket.peeraddr[3]][:low] == nil    
                @peers[socket.peeraddr[3]][:low], @peers[socket.peeraddr[3]][:high] = select_interval() 
              if @peers[socket.peeraddr[3]][:low] == false
                response = "no_interval"
              else
              response = @peers[socket.peeraddr[3]][:low].to_s + "," + @peers[socket.peeraddr[3]][:high].to_s
            end         
          #caso o peer tenha se desconectado anteriormente sem terminar o trabalho
          else 
            response = @peers[socket.peeraddr[3]][:low].to_s + "," + @peers[socket.peeraddr[3]][:high].to_s
          end 
          }                       
        when "peer_interval"
          if @interval[:low] == false
            response = "no_interval"
          else
            response = @interval[:low].to_s + "," + @interval[:high].to_s
          end
        when "ping"
          response = "pong"
        when "finish_interval_computation"
          @mutex.synchronize {
            @peers[socket.peeraddr[3]][:low] = @peers[socket.peeraddr[3]][:high] = false
          }
          response = "ok"
        when "is_prime"
          puts @number.to_s + " é primo"
          socket.puts "ok"
          exit(0)
        when "not_prime"
          puts "Number is not prime " + message[1] + " divides " + @number.to_s
          socket.puts "ok"
          exit(0) 
        else
          response = "Unknow command"
        end
        puts "response: " + response
        socket.puts response
      socket.close
    }
  end

  def select_interval
    if @remaining_interval[:low] >= @remaining_interval[:high]
      if @interval_queue.empty?
        return [false, false]
      end
      interval = @interval_queue.shift
      return [interval[:low], interval[:high]]
    end
    low = @remaining_interval[:low]
    if @remaining_interval[:low] + @quantum + 1 > @remaining_interval[:high]
      high = @remaining_interval[:high]
      @remaining_interval[:low] = @remaining_interval[:high]
    else
      high = low + @quantum
      @remaining_interval[:low] += (@quantum + 1) 
    end

    return [low, high]
  end

  def try_connect(id)
    begin 
      return TCPSocket.open(id, @port)
    rescue
      return false
    end
  end

  def check_end
    if @remaining_interval[:low] >= @remaining_interval[:high] && @interval_queue.empty?
      @mutex.synchronize {
      @peers.each_key do |id| 
        if (@peers[id][:low] != false && @peers[id][:high] != false)
          puts "teste pendente: " + @peers[id][:low].to_s + ", " + @peers[id][:high].to_s
          socket = try_connect(id)
          if socket == false
            puts "maquina " + id + " caiu, colocando intervalo na fila de pendentes"
            @interval_queue.push({low: @peers[id][:low], high: @peers[id][:high]})
            @peers[id][:low] = @peers[id][:high] = false
          else
            socket.puts "ping"
            socket.gets
          end
          return @prime = false
        end
      end
      }
      return @prime = true
    end
    return @prime = false
  end

  def primality_test
    tr = Thread.new {
      loop {
        puts "testing interval " + @interval[:low].to_s + "," + @interval[:high].to_s
        if @interval[:low] != false and @interval[:low] != false and @interval[:low] != nil and @interval[:high] != nil
          i = @interval[:low]
          while i <= @interval[:high] do
            if @number % i == 0
              puts "Não é primo " + i.to_s + " divide " + @number.to_s
              message = "not_prime" + " " + i.to_s
              broadcast(message)
              exit(0)
            end
            i += 1
          end
          message = "finish_interval_computation" + " " + @interval[:low].to_s + "," + @interval[:high].to_s
          broadcast(message)
        end
        if @leader
          if check_end() == true
            broadcast("is_prime")
            puts "O número é primo"
            exit(0)
          end 
          @mutex.synchronize {
            @interval[:low], @interval[:high] = select_interval()
          } 
          if @interval[:low] == false || @interval[:high] == false
            sleep(0.1)
          end
        else
          conn_failed = false
          begin 
            socket = TCPSocket.open(@leader_id, @port)
            socket.puts "new_interval"
            response = socket.gets.chomp
          rescue
            conn_failed = true
          end
          if conn_failed || response == "no_interval"
            sleep(0.1)
            @mutex.synchronize {
              @interval[:low] = @interval[:high] = false
            }
          else
            @mutex.synchronize {
              response = response.split(",")
              @interval[:low], @interval[:high] = response[0].to_i, response[1].to_i
            }          
          end

        end
      }
    }
  end

  def heartbeat
    @mutex.synchronize {
    @peers.each_key do |id|
      socket = try_connect(id)
      if socket == false
        @peers[id][:status] = "lost"
        puts "maquina " + id + " caiu, colocando intervalo na fila de pendentes"
        if @peers[id][:low] != false and @peers[id][:low] != nil
          @mutex.synchronize {
            @interval_queue << {low: @peers[id][:low], high: @peers[id][:high]}
          }
          @peers[id][:low] = @peers[id][:high] = false 
        end
      else
        socket.puts "ping"
        socket.gets
      end  
    end
    }
  end

  def broadcast(message)
    @peer_mutex.synchronize {
      @peers.each_key do |id|
        begin
          if message == "is_prime" || message == "not_prime"
            puts "transmitindo mensagem de fim para o peer " + id
          end
          socket = TCPSocket.open(id, @port)
          socket.puts message
          socket.gets 
        rescue
          next
        end
      end
    }
  end

  def connect_peers
    ips = ipscan()
    ips.each do |ip|
      puts "ip = " + ip
    end
    ips = ipscan()
    ips.each do |ip|
      begin
        if ip == @id
          next
        end 
        response = nil
        socket = Socket.tcp(ip, @port, connect_timeout: 1) { |socket|
          puts "Connected to peer from " + ip          
          socket.print "leader?"
          socket.close_write
          response = socket.read
        }
        puts "Received response " + response.chomp 
        response = response.split(/[ \r\n]/)
        if response[0] == "yes"
          puts "Peer with ip " + ip + " is the leader"
          @leader_id = ip
          socket = TCPSocket.open(ip, @port)
          socket.puts "get_computation_info"
          response = socket.gets
          puts "Received response " + response.chomp
          response = response.split(/[ \r\n]/)
          @number = response[0].to_i
          x, y = response[1].split(",")
          @remaining_interval[:low], @remaining_interval[:high] = x.to_i, y.to_i
          for i in 2..(response.size - 1) 
            low, high = response[i].split(",")
            @interval_queue << {low: low.to_i, high: high.to_i}
          end
          socket = TCPSocket.open(ip, @port)
          puts "Requesting new interval"
          socket.puts "new_interval"
          response = socket.gets
          puts "Response: " + response
          if response == "no_interval"
            @interval[:low] = @interval[:high] = false
          else
            response = response.chomp.split(/[,\r\n]/) 
            @interval[:low] = response[0].to_i
            @interval[:high] = response[1].to_i
          end
        end
        @peers[ip] = Hash.new
        socket = TCPSocket.open(ip, @port)
        puts "Requesting peer interval"
        socket.puts "peer_interval"
        response = socket.gets
        puts "Response " + response
        if response == "no_interval"
          @peers[ip][:low] = false
          @peers[ip][:high] = false
        else
          response = response.chomp.split(/[,\r\n]/)
          @peers[ip][:low] = response[0].to_i
          @peers[ip][:high] = response[1].to_i
        end
      rescue
      end       
    end
    if @leader_id == nil
      puts "Não foi possível encontrar o líder"
      exit(1)
    end
    puts "End finding connections"
  end

  def leader_election
  end

  def ipscan
    ips = IPAddr.new("192.168.1.0/24").to_range
    ip_array = []
    threads = ips.map do |ip|
      Thread.new do
        status = system("ping -q -W 1 -c 1 #{ip}",
                      [:err, :out] => "/dev/null")
        ip_array << ip.to_s if status
      end
    end
    threads.each {|t| t.join}
    return ip_array
  end
end

if ARGV[0] == nil 
  Peer.new(2000)
else 
  Peer.new(2000, ARGV[0].to_i)
end