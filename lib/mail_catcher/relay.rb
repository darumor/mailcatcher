require 'eventmachine'
require 'thread'
require 'net/smtp'

class MailCatcher::Relay
  def initialize(ip='127.0.0.1', port='25', active=false, domain=nil, account=nil, password=nil)
    @ip = ip
    @port = port
    @active = active
    @domain = domain
    @account = account
    @password = password

    @for_messages = Mutex.new
    @cv = ConditionVariable.new

  end

  def message_added       
    if @active
       @cv.signal
    end
  end

  def run!
    @message_sender_thread = Thread.new {
      send_messages
    }
    @message_sender_thread.join
  end

  def send_messages
    while @active
      @for_messages.synchronize {
        messages_to_send = MailCatcher::Mail.messages
        messages_to_send.each do |msg|
          send_message msg
          sleep (1.0 / 1.0)  # send approx. 10 msg per second     
        end
        @cv.wait(@for_messages) if MailCatcher::Mail.messages.empty?
      }
    end
  end

  def send_message message
    msg_to_send = message[:source]
    Net::SMTP.start(@ip, @port, @domain, @account, @password, :plain) do |smtp|
      smtp.send_message(msg_to_send, message[:sender], message[:recipients])
    end
  end

  def kill! nice=true
    @active = false   #let message_sender_thread to exit gracefully
    @message_sender_thread.exit if !nice     #kill message_sender_thread instantly
  end
end
