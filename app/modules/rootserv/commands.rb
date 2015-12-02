require "active_record"
require "chronic_duration"
require "date"

require_relative "../../libs/irc"

class RootservAccess < ActiveRecord::Base
end

class RootservCommands

  @irc = nil

  def get_flags account
    RootservAccess.establish_connection(@db)
    query = RootservAccess.where(name: account.downcase)
    (RootservAccess.connection.disconnect!; return false) if query.count == 0
    query.each { |q|
      RootservAccess.connection.disconnect!
      return q["flags"].to_s
    }
    return false
  end

  def has_entry account
    RootservAccess.establish_connection(@db)
    query = RootservAccess.where(name: account.downcase)
    (RootservAccess.connection.disconnect!; return false) if query.count == 0
    query.each { |q|
      RootservAccess.connection.disconnect!
      return q
    }
    return false
  end

  def has_flag account, flags
    our_flags = get_flags account
    return false if !our_flags

    flags.split(//).each { |f| return true if our_flags.include? f }
    return false
  end

  def has_flags account
    flags = get_flags account
    return false if !flags
    return flags
  end

  def handle_access_add hash
    target = hash["from"]

    params = hash["parameters"].split(' ')

    if params[1].nil? or params[1].empty?
      return @irc.notice @client_sid, target, "User not specified"
    end

    if params[2].nil? or params[2].empty?
      return @irc.notice @client_sid, target, "Flags not specified"
    end

    newuser  = params[1]
    newflags = params[2].upcase.split(//).delete_if{|x| x == 'Z'}.sort!
    newflags = newflags.uniq.join

    if newflags.empty?
      @irc.notice @client_sid, target, "Flags not specified. Note: Z may not be distributed."
      return
    end

    if !has_entry newuser
      RootservAccess.establish_connection(@db)
      query = RootservAccess.new
      query.name  = newuser
      query.flags = newflags
      query.added_by = @irc.get_account_from_uid target
      query.added = Time.new.to_i
      query.save
      RootservAccess.connection.disconnect!
      @irc.notice @client_sid, target, "Added #{newuser} with flags #{newflags}"
    else
      @irc.notice @client_sid, target, "#{newuser} already has access to #{@rs["nick"]}"
    end
  end

  def handle_access_list hash
    target = hash["from"]
    @irc.notice @client_sid, target, "#{@rs["nick"]} access list:"
    @irc.notice @client_sid, target, " "
    RootservAccess.establish_connection(@db)
    RootservAccess.all.each do |user|
      @irc.notice @client_sid, target, "#{user[:id]}: \x02#{user[:name]}\x02 with flags \x02#{user[:flags]}\x02"
    end
    @irc.notice @client_sid, target, " "
    @irc.notice @client_sid, target, "End of access list"
    RootservAccess.connection.disconnect!
  end

  def handle_access_edit hash
    target = hash["from"]

    params = hash["parameters"].split(' ')

    if params[1].nil? or params[1].empty?
      return @irc.notice @client_sid, target, "User not specified"
    end

    if params[2].nil? or params[2].empty?
      return @irc.notice @client_sid, target, "Flags not specified"
    end

    newuser  = params[1]
    newflags = params[2].upcase.split(//).delete_if{|x| x == 'Z'}.sort!
    newflags = newflags.uniq.join

    if newflags.empty?
      @irc.notice @client_sid, target, "Flags not specified. Note: Z may not be distributed."
      return
    end

    if has_entry newuser
      if has_flag newuser, 'Z'
        if !newflags.include? 'Z'
          newflags << 'Z'
        end
      end
      RootservAccess.establish_connection(@db)
      query = RootservAccess.where(name: newuser).first
      query.flags = newflags
      query.modified = Time.new.to_i
      query.save
      RootservAccess.connection.disconnect!
      @irc.notice @client_sid, target, "Changed #{newuser}'s flags to #{newflags}"
    else
      @irc.notice @client_sid, target, "#{newuser} does not have access to #{@rs["nick"]}"
    end
  end

  def handle_access_del hash
    target = hash["from"]

    params = hash["parameters"].split(' ')

    if params[1].nil? or params[1].empty?
      return @irc.notice @client_sid, target, "User not specified"
    end

    olduser = params[1]

    if has_entry olduser
      if has_flag olduser, 'Z'
        @irc.notice @client_sid, target, "#{olduser} has the founder flag. Their access cannot be deleted."
        return
      end
      RootservAccess.establish_connection(@db)
      query = RootservAccess.where(name: olduser)
      query.delete_all
      RootservAccess.connection.disconnect!
      @irc.notice @client_sid, target, "Deleted #{olduser}'s access"
    else
      @irc.notice @client_sid, target, "#{olduser} does not have access"
    end
  end

  def send_data name, sock, string
    time = Time.now
    puts "[~S] [#{name}] [#{time.strftime("%Y-%m-%d %H:%M:%S")}] #{string}"
    sock.send string, 0
  end

  def sendto_debug message
    @rs["debug_channels"].split(',').each { |x| @irc.privmsg @client_sid, x, message } if @rs["debug_channels"]
    @rs["control_channels"].split(',').each { |x| @irc.privmsg @client_sid, x, message }
  end

  def handle_access hash
    target = hash["from"]
    if !has_flag(@irc.get_account_from_uid(target), 'FZ')
      @irc.notice @client_sid, target, "Permission denied."
      sendto_debug "Denied access to #{@irc.get_nick_from_uid target} [#{__method__.to_s}]"
      return
    end

    return @irc.notice @client_sid, target, "Need more parameters" if hash["parameters"].empty?

    params = hash["parameters"].split(' ')

    case params[0].downcase
    when "list"
      handle_access_list hash
    when "add"
      handle_access_add hash
    when "edit"
      handle_access_edit hash
    when "del"
      handle_access_del hash
    else
      @irc.notice @client_sid, target, "#{params[0].upcase} is an unknown modifier"
    end

  end

  def handle_svsnick hash
    target = hash["from"]
    if !has_flag(@irc.get_account_from_uid(target), 'FNZ')
      @irc.notice @client_sid, target, "Permission denied."
      sendto_debug "Denied access to #{@irc.get_nick_from_uid target} [#{__method__.to_s}]"
      return
    end

    return @irc.notice @client_sid, target, "User not specified" if hash["parameters"].empty?

    params = hash["parameters"].split(' ')

    if params[1].nil? or params[1].empty?
      return @irc.notice @client_sid, target, "New nickname not specified"
    else
      targetobj = @irc.get_nick_object params[0]
      return @irc.notice @client_sid, target, "Could not find user #{params[0]}" if !targetobj
      @irc.ts6_fnc @parameters["sid"], params[1], targetobj
      @irc.notice @client_sid, target, "Changed #{targetobj["Nick"]}'s nick to #{params[1]}"
      @irc.wallop @client_sid, "\x02#{@irc.get_nick_from_uid target}\x02 used \x02SVSNICK\x02 on \x02#{targetobj["Nick"]}\x02 => \x02#{params[1]}\x02"
    end
  end

  def handle_kill hash
    target = hash["from"]
    if !has_flag(@irc.get_account_from_uid(target), 'FKZ')
      @irc.notice @client_sid, target, "Permission denied."
      sendto_debug "Denied access to #{@irc.get_nick_from_uid target} [#{__method__.to_s}]"
      return
    end

    return @irc.notice @client_sid, target, "User not specified" if hash["parameters"].empty?

    params = hash["parameters"].split(' ')

    targetobj = @irc.get_nick_object params[0]
    sourceobj = @irc.get_uid_object @client_sid
    return @irc.notice @client_sid, target, "Could not find user #{params[0]}" if !targetobj

    if params.count == 1
      killmsg = "Requested"
    else
      killmsg = params[1..-1].join(' ')
    end

    @irc.kill sourceobj, targetobj["UID"], killmsg
    @irc.notice @client_sid, target, "Killed #{targetobj["Nick"]}"
    @irc.wallop @client_sid, "\x02#{@irc.get_nick_from_uid target}\x02 used \x02KILL\x02 on \x02#{targetobj["Nick"]}\x02"
  end

  def handle_whois hash, uid = false
    target = hash["from"]
    if !has_flag(@irc.get_account_from_uid(target), 'FWZ')
      @irc.notice @client_sid, target, "Permission denied."
      sendto_debug "Denied access to #{@irc.get_nick_from_uid target} [#{__method__.to_s}]"
      return
    end

    return @irc.notice @client_sid, target, "User not specified" if hash["parameters"].empty?

    nick = hash["parameters"].split(' ')[0]
    if uid
      targetobj = @irc.get_uid_object nick
    else
      targetobj = @irc.get_nick_object nick
    end
    return @irc.notice @client_sid, target, "Could not find #{uid ? "uid" : "user"} #{nick}" if !targetobj

    @irc.notice @client_sid, target, "Information for \x02#{nick}\x02:"
    @irc.notice @client_sid, target, "UID: #{targetobj["UID"]}"
    @irc.notice @client_sid, target, "Signed on: #{DateTime.strptime(targetobj["CTime"], '%s').in_time_zone('America/New_York').strftime("%A %B %d %Y @ %l:%M %P %z")} (#{ChronicDuration.output(Time.new.to_i - targetobj["CTime"].to_i)} ago)"
    @irc.notice @client_sid, target, "Real nick!user@host: #{targetobj["Nick"]}!#{targetobj["Ident"]}@#{targetobj["Host"] == "*" ? targetobj["IP"] : targetobj["Host"]}"
    @irc.notice @client_sid, target, "Server: #{targetobj["Server"]}"
    @irc.notice @client_sid, target, "Services account: #{targetobj["NickServ"] == "*" ? "Not logged in." : targetobj["NickServ"]}"
    @irc.notice @client_sid, target, "User modes: #{targetobj["UModes"]}"
    @irc.notice @client_sid, target, "Channels: #{@irc.get_user_channels(targetobj["UID"]).join(' ')}"
    @irc.notice @client_sid, target, "End of whois information"
  end

  def handle_chaninfo hash
    target = hash["from"]
    if !has_flag(@irc.get_account_from_uid(target), 'FCZ')
      @irc.notice @client_sid, target, "Permission denied."
      sendto_debug "Denied access to #{@irc.get_nick_from_uid target} [#{__method__.to_s}]"
      return
    end

    return @irc.notice @client_sid, target, "Channel not specified" if hash["parameters"].empty?

    chan = hash["parameters"].split(' ')[0]
    chanhash = @irc.get_chan_info chan
    return @irc.notice @client_sid, target, "Could not find channel #{chan}" if !chanhash
    usersarray = @irc.get_users_in_channel chan
    @irc.notice @client_sid, target, "Information for \x02#{chanhash[:channel]}\x02:"
    @irc.notice @client_sid, target, "Created on #{DateTime.strptime(chanhash[:ctime].to_s, '%s').in_time_zone('America/New_York').strftime("%A %B %d %Y @ %l:%M %P %z")} (#{ChronicDuration.output(Time.new.to_i - chanhash[:ctime].to_i)} ago)"
    @irc.notice @client_sid, target, "Mode: #{chanhash[:modes]}"
    @irc.notice @client_sid, target, "Users:"
    if !usersarray.empty?
      usersarray.each { |x| @irc.notice @client_sid, target, "- #{x}" }
      @irc.notice @client_sid, target, "#{usersarray.count} users in #{chanhash[:channel]}"
    else
      @irc.notice @client_sid, target, "Channel is empty."
    end
    @irc.notice @client_sid, target, "End of chaninfo"
  end

  def handle_privmsg hash
    target = hash["from"]

    # Because of the ease of abuse, send *everything* to debug.
    sendto_debug "#{@irc.get_nick_from_uid target}: #{hash["command"]} #{hash["parameters"]}"

    case hash["command"].downcase
    when "help"
      # TODO
      if !hash["parameters"].empty?
        @irc.notice @client_sid, target, "***** #{@rs["nick"]} Help *****"
        @irc.notice @client_sid, target, "Extended help not implemented yet."
        @irc.notice @client_sid, target, "***** End of Help *****"
        return
      end

      @irc.notice @client_sid, target, "***** #{@rs["nick"]} Help *****"
      @irc.notice @client_sid, target, "#{@rs["nick"]} allows for extra control over the network. This is intended for debug use only. i.e. don't abuse #{@rs["nick"]}."
      @irc.notice @client_sid, target, "For more information on a command, type \x02/msg #{@rs["nick"]} help <command>\x02"
      @irc.notice @client_sid, target, "The following commands are available:"
      @irc.notice @client_sid, target, "[F] ACCESS                      Modifies #{@rs["Nick"]}'s access list"
      @irc.notice @client_sid, target, "[C] CHANINFO <#channel>         Returns information on the channel"
      @irc.notice @client_sid, target, "[F] FLAGS                       Modifies #{@rs["Nick"]}'s access list"
      @irc.notice @client_sid, target, "[K] KILL <nick> [message]       Kills a client"
      @irc.notice @client_sid, target, "[N] SVSNICK <nick> <newnick>    Changes nick's name to newnick"
      @irc.notice @client_sid, target, "[W] UID <uid>                   Returns information on the UID"
      @irc.notice @client_sid, target, "[W] WHOIS <nick>                Returns information on the nick"
      @irc.notice @client_sid, target, " "
      myflags = get_flags(@irc.get_account_from_uid target)
      if !myflags
        @irc.notice @client_sid, target, "You do not have any flags."
      else
        @irc.notice @client_sid, target, "Your flags: #{myflags}"
      end
      @irc.notice @client_sid, target, " "
      @irc.notice @client_sid, target, "***** End of Help *****"

    when "chaninfo"
      handle_chaninfo hash

    when "svsnick"
      handle_svsnick hash

    when "kill"
      handle_kill hash

    when "whois"
      handle_whois hash

    when "uid"
      handle_whois hash, true

    when "access", "flags"
      handle_access hash

    else
      @irc.notice @client_sid, target, "#{hash["command"].upcase} is an unknown command."

    end
  end

  def init e, m, c, d
    @e = e
    @m = m
    @c = c
    @d = d

    @config = c.Get
    @db = @config["connections"]["databases"]["test"]
    @parameters = @config["connections"]["clients"]["irc"]["parameters"]
    @client_sid = "#{@parameters["sid"]}000004"
    @initialized = false

    @e.on_event do |type, hash|
      if type == "Rootserv-Chat"
        if !@initialized
          @config = @c.Get
          @db = @config["connections"]["databases"]["test"]
          @rs = @config["rootserv"]
          @irc = IRCLib.new hash["name"], hash["sock"], @config["connections"]["databases"]["test"]
          @initialized = true
        end
        handle_privmsg hash if hash["msgtype"] == "PRIVMSG"
      end
    end
  end

end
