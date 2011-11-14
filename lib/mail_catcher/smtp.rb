require 'eventmachine'

class MailCatcher::Smtp < EventMachine::Protocols::SmtpServer
  def current_message
    @current_message ||= {}
  end

  def relay_server
    @@relay_server || Relay.new
  end

  def self.relay_server= relay
    @@relay_server = relay
  end

  def receive_reset
    @current_message = nil
    true
  end

  def receive_sender(sender)
    current_message[:sender] = sender
    true
  end

  def receive_recipient(recipient)
    current_message[:recipients] ||= []
    current_message[:recipients] << recipient
    true
  end

  def receive_data_chunk(lines)
    current_message[:source] ||= ""
    current_message[:source] += lines.join("\n")
    true
  end

  def receive_message
    MailCatcher::Mail.add_message current_message
    puts "==> SMTP: Received message from '#{current_message[:sender]}' (#{current_message[:source].length} bytes)"
    relay_server.message_added
    true
  rescue
    puts "*** Error receiving message: #{current_message.inspect}"
    puts "    Exception: #{$!}"
    puts "    Backtrace:"
    $!.backtrace.each do |line|
      puts "       #{line}"
    end
    puts "    Please submit this as an issue at http://github.com/sj26/mailcatcher/issues"
    false
  ensure
    @current_message = nil
  end
end
