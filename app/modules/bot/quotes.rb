require "active_record"

require_relative "../../libs/irc"

class Quote < ActiveRecord::Base
end

class BotQuotes

  def send_data name, sock, string
    time = Time.now
    puts "[~S] [#{name}] [#{time.strftime("%Y-%m-%d %H:%M:%S")}] #{string}"
    sock.send string, 0
  end

  def handle_privmsg hash, flags
    return if (flags & Flags::Quotes) == 0

    target = hash["target"]
    target = hash["from"] if target == @client_sid

    return if !['#', '&'].include? target[0]

    if ["!q", "!quote"].include? hash["command"].downcase
      cp = hash["parameters"].split(' ')
      cp = [""] if cp.empty?

      case cp[0].downcase
      when "add"
        Quote.establish_connection(@config["connections"]["databases"]["test"])
        quote         = Quote.new
        quote.channel = target
        quote.person  = @irc.get_nick_from_uid(hash["from"])
        quote.quote   = hash["parameters"].split(' ')[1..-1].join(' ')
        quote.time    = Time.now.to_i - 18000
        quote.save
        Quote.connection.disconnect!
        @irc.privmsg @client_sid, target, "[QUOTE] Saved quote ##{quote.id}!"

      when "del"
        if !@irc.is_chan_founder(target, hash["from"]) and !@irc.is_chan_admin(target, hash["from"]) and !@irc.is_chan_op(target, hash["from"])
          @irc.notice @client_sid, hash["from"], "You need at least +o remove quotes from the database."
          return
        end
        Quote.establish_connection(@config["connections"]["databases"]["test"])
        query = Quote.where(id: cp[1], channel: target)

        if query.count == 0
          @irc.privmsg @client_sid, target, "Quote ID #{cp[1]} does not exist for #{target}."
          Quote.connection.disconnect!
          return
        end

        query.delete_all
        @irc.privmsg @client_sid, target, "Deleted quote ID ##{cp[1]}."
        Quote.connection.disconnect!

      when "search"
        Quote.establish_connection(@config["connections"]["databases"]["test"])
        query = Quote.where('channel = ? AND quote LIKE ?', target, "%#{cp[1]}%")

        if query.count == 0
          @irc.privmsg @client_sid, target, "No quotes could be found for #{target}."
          Quote.connection.disconnect!
          return
        end

        Thread.new do
          query.each do |row|
            time = Time.at(row.time.to_i).strftime("%m/%d/%y @ %-l:%M %p Eastern")
            @irc.privmsg @client_sid, target, "[QUOTE] ##{row.ID}: Submitted By: #{row.Person} - #{time} - #{row.Quote}"
            sleep 0.4
          end
          Quote.connection.disconnect!
        end

      when ""
        Quote.establish_connection(@config["connections"]["databases"]["test"])
        query = Quote.where(channel: target).order("RAND()").first

        if query.nil?
          @irc.privmsg @client_sid, target, "No quotes could be found for #{target}."
          Quote.connection.disconnect!
          return
        end

        return if query.time.nil?

        time = Time.at(query.time.to_i).strftime("%m/%d/%y @ %-l:%M %p Eastern")
        @irc.privmsg @client_sid, target, "[QUOTE] ##{query.id}: Submitted By: #{query.person} - #{time} - #{query.quote}"
        Quote.connection.disconnect!

      when /\A\d+\z/
        Quote.establish_connection(@config["connections"]["databases"]["test"])
        query = Quote.where(id: cp[0], channel: target).first

        if query.nil?
          @irc.privmsg @client_sid, target, "[QUOTE] ID #{cp[0]} does not exist."
          Quote.connection.disconnect!
          return
        end

        return if query.time.nil?

        time = Time.at(query.time.to_i).strftime("%m/%d/%y @ %-l:%M %p Eastern")
        @irc.privmsg @client_sid, target, "[QUOTE] ##{query.id}: Submitted By: #{query.person} - #{time} - #{query.quote}"
        Quote.connection.disconnect!

      else
        @irc.privmsg @client_sid, target, "[QUOTE] Unknown parameter"

      end
    end
  end

  def init e, m, c, d
    @e = e
    @m = m
    @c = c
    @d = d

    @config = c.Get
    parameters = @config["connections"]["clients"]["irc"]["parameters"]
    @client_sid = "#{parameters["sid"]}000003"
    @initialized = false

    Quote.establish_connection(@config["connections"]["databases"]["test"])
    Quote.connection.disconnect!

    @e.on_event do |type, hash, flags|
      if type == "Bot-Chat"
        if !@initialized
          config = @c.Get
          @irc = IRCLib.new hash["name"], hash["sock"]
          @initialized = true
        end
        handle_privmsg hash, flags if hash["msgtype"] == "PRIVMSG"
      end
    end
  end
end
