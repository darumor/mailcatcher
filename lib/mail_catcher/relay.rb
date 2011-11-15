require 'eventmachine'
require 'thread'
require 'net/smtp'

class MailCatcher::Relay
  def initialize(ip='127.0.0.1', port='25', active=false, domain='localhost', account='', password='')
    @ip = ip
    @port = port
    @active = active
    @domain = domain
    @account = account
    @password = password

    @for_messages = Mutex.new
    @cv = ConditionVariable.new
    @message_queue = []
    @queue_updater_running = false

    run!
    puts "RELAY: Initialized."
  end

  def run!
    @message_sender_thread = Thread.new {
      send_messages
    }
  end


  #todo may need some refactoring...
  
  def message_added
    if @active
      # allow adding many messages between queue updates
      if !@queue_updater_running
        @queue_updater_running = true
        Thread.new {
          @for_messages.synchronize {
            puts "RELAY: updating message queue"
            @message_queue = MailCatcher::Mail.whole_messages
            @queue_updater_running = false
            @cv.signal              #queue updated let sender proceed
          }
        }
      end
    end
  end

  def send_messages
    while @active
      @for_messages.synchronize {
        puts "RELAY: Sending #{@message_queue.size} messages..."
        @message_queue.each do |msg|
          send_message msg        #send it
          begin
            MailCatcher::Mail.delete_single_message msg["id"]   #remove it from the db
          rescue => e
            puts "RELAY: deletion error: #{e}"
            @active = false    # prevent eternal loop
          end
          sleep (1.0 / 10.0)  # send approx. 10 msg per second
        end
        @cv.wait(@for_messages)               # wait for more messages
      }
    end
  end

  def send_message message
    # turn keys from strings to syms
    msg_copy = {}
    message.each do |key, value|
      msg_copy[key.to_sym] = value
    end

    begin
      Net::SMTP.start(@ip, @port, @domain, @account, @password, :plain) do |smtp|
        smtp.send_message(msg_copy[:source], msg_copy[:sender], msg_copy[:recipients])
     end
    rescue => e
      "RELAY: SMTP-ERROR #{e}"  
    end
  end

  def kill! nice=true
    @active = false   #let message_sender_thread to exit gracefully
    @message_sender_thread.exit if !nice     #kill message_sender_thread instantly
  end
end
