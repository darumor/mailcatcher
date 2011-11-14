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
    run!
    puts "RELAY: Initialized."
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
  end

  def send_messages
    while @active
      @for_messages.synchronize {
        messages_to_send = MailCatcher::Mail.whole_messages
        #puts "RELAY: Sending #{messages_to_send.size} messages..."
        messages_to_send.each do |msg|
          id = msg["id"]
          msg_to_send = msg.merge({
                  "formats" => ["source",
                               ("html" if MailCatcher::Mail.message_has_html? id),
                               ("plain" if MailCatcher::Mail.message_has_plain? id),
            ].compact,
                  "attachments" => MailCatcher::Mail.message_attachments(id).map do |attachment|
                      attachment.merge({"href" => "/messages/#{escape(id)}/#{escape(attachment['cid'])}"})
                  end
            })

          send_message msg_to_send
          begin
            MailCatcher::Mail.delete_single_message id
          rescue => e
            puts "RELAY: deletion error: #{e}"
            @active = false    # prevent eternal loop
          end
          sleep (1.0 / 10.0)  # send approx. 10 msg per second
        end
        @cv.wait(@for_messages) if MailCatcher::Mail.messages.empty?
      }
    end
  end

  def send_message message
    msg_copy = {}
    message.each do |key, value|
      msg_copy[key.to_sym] = value
    end

    #puts "RELAY: now sending: "
    #puts "----------------"     #debug
    #puts msg_copy[:source]      #debug
    #puts "----------------"     #debug

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
