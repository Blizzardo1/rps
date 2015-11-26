require "active_record"

require_relative "../libs/irc"

class BotChannel < ActiveRecord::Base
end

class BotClient

  def me_user_notice recp, message
    @irc.notice @client_sid, recp, message
  end

  def send_data name, sock, string
    time = Time.now
    puts "[~S] [#{name}] [#{time.strftime("%Y-%m-%d %H:%M:%S")}] #{string}"
    sock.send string, 0
  end

  def connect_client
    @irc.add_client @parameters["sid"], "#{@client_sid}", "Bot", "+ioS", "Bot", "GeeksIRC.net", "Bot"
  end

  def is_channel_signedup channel
    BotChannel.establish_connection(@config["connections"]["databases"]["test"])
    query = BotChannel.where('Channel = ?', channel)
    return true if query.count == 1
    BotChannel.connection.disconnect!
    return false
  end

  def signup_channel channel
    BotChannel.establish_connection(@config["connections"]["databases"]["test"])
    query = BotChannel.new
    query.Channel = channel.downcase
    query.save
    BotChannel.connection.disconnect!
  end

  def remove_channel channel
    BotChannel.establish_connection(@config["connections"]["databases"]["test"])
    query = BotChannel.where('Channel = ?', channel.downcase)
    (BotChannel.connection.disconnect!; return false) if query.count == 0
    query.delete_all
    BotChannel.connection.disconnect!
    return true
  end

  def join_channels
    BotChannel.establish_connection(@config["connections"]["databases"]["test"])
    queries = BotChannel.select(:Channel)
    return if queries.count == 0
    queries.each do |query|
      @irc.client_join_channel @client_sid, query.Channel
      @irc.client_set_mode @client_sid, "#{query.Channel} +o #{@client_sid}"
      @irc.privmsg @client_sid, @config["debug-channels"]["bot"], "JOINED: #{query.Channel}"
    end
    BotChannel.connection.disconnect!
  end

  def handle_privmsg hash
    @e.Run "Bot-Chat", hash
    target = hash["target"]
    target = hash["from"] if target == @client_sid

    return if target != @client_sid

    if hash["command"].downcase == "help"
      me_user_notice, target, "***** Bot Help *****"
      me_user_notice, target, "Bot allows channel owners to limit the amount of joins that happen in certain amount of time. This is to prevent join floods."
      me_user_notice, target, "The following commands are available:"
      me_user_notice, target, "REQUEST                   Request Bot for your channel."
      me_user_notice, target, "REMOVE                    Remove Bot from your channel."
      me_user_notice, target, "***** End of Help *****"
      me_user_notice, target, "If you're having trouble or you need additional help, you may want to join the help channel #help."
    end

    if hash["command"].downcase == "request"
      return me_user_notice, target, "[ERROR] No chatroom was specified." if hash["parameters"].nil?
      return me_user_notice, target, "[ERROR] The channel does not exist on this network." if !@irc.does_channel_exist hash["parameters"]
      return me_user_notice, target, "[ERROR] You must be founder of #{hash["parameters"]} in order to add Bot to the channel." if !@irc.is_chan_founder hash["parameters"], target and !@irc.is_oper_uid target
      return me_user_notice, target, "[ERROR] This channel is already signed up for Bot." if is_channel_signedup hash["parameters"]
      signup_channel hash["parameters"]
      me_user_notice, target, "[SUCCESS] Bot has joined #{hash["parameters"]}."
      @irc.client_join_channel @client_sid, hash["parameters"]
      @irc.client_set_mode @client_sid, "#{hash["parameters"]} +o #{@client_sid}"
      @irc.privmsg @client_sid, @config["debug-channels"]["bot"], "REQUEST: #{hash["parameters"]} - (#{@irc.get_nick_from_uid(target)})" if @irc.is_chan_founder hash["parameters"], target
      @irc.privmsg @client_sid, @config["debug-channels"]["bot"], "REQUEST: #{hash["parameters"]} - (#{@irc.get_nick_from_uid(target)}) [OPER Override]" if @irc.is_oper_uid target
    end

    if hash["command"].downcase == "remove"

      return me_user_notice, target, "[ERROR] No chatroom was specified." if hash["parameters"].nil?
      return me_user_notice, target, "[ERROR] The channel does not exist on this network." if !@irc.does_channel_exist hash["parameters"]
      return me_user_notice, target, "[ERROR] You must be founder of #{hash["parameters"]} in order to remove Bot from the channel." if !@irc.is_chan_founder hash["parameters"], target and !@irc.is_oper_uid target
      return me_user_notice, target, "[ERROR] This channel is not signed up for Bot." if !is_channel_signedup hash["parameters"]

      remove_channel hash["parameters"]
      me_user_notice, target, "[SUCCESS] Bot has left #{hash["parameters"]}."
      @irc.client_part_channel @client_sid, hash["parameters"]
      @irc.privmsg @client_sid, @config["debug-channels"]["bot"], "REMOVED: #{hash["parameters"]} - (#{@irc.get_nick_from_uid(target)})" if @irc.is_chan_founder hash["parameters"], target
      @irc.privmsg @client_sid, @config["debug-channels"]["bot"], "REMOVED: #{hash["parameters"]} - (#{@irc.get_nick_from_uid(target)}) [OPER Override]" if @irc.is_oper_uid target
    end
  end

  def init e, m, c, d
    @e = e
    @m = m
    @c = c
    @d = d

    @config = c.Get
    @parameters = @config["connections"]["clients"]["irc"]["parameters"]
    @client_sid = "#{@parameters["sid"]}000003"
    @initialized = false

    @e.on_event do |type, name, sock|
      if type == "IRCClientInit"
        config = @c.Get
        @irc = IRCLib.new name, sock, @config["connections"]["databases"]["test"]
        connect_client
        sleep 1
        join_channels
        @initialized = true
      end
    end

    @e.on_event do |type, hash|
      if type == "IRCChat"
        if !@initialized
          config = @c.Get
          @irc = IRCLib.new hash["name"], hash["sock"], config["connections"]["databases"]["test"]
          connect_client
          sleep 1
          join_channels
          @initialized = true
          sleep 1
        end
        handle_privmsg hash if hash["msgtype"] == "PRIVMSG"
      end
    end
  end
end
