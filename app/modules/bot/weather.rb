require "wunderground"

require_relative "../../libs/irc"

class BotWeather

  def send_data name, sock, string
    time = Time.now
    puts "[~S] [#{name}] [#{time.strftime("%Y-%m-%d %H:%M:%S")}] #{string}"
    sock.send string, 0
  end

  def run parameters
    array = []
    begin
      data = @w_api.conditions_for(parameters)
      data = data["current_observation"]

      if data.nil?
        array.push("No data could be found.")
        return array
      end

      location = data["observation_location"]["full"]
      lastupdated = data["observation_time"]
      description = data["nowcast"]
      wind = data["wind_string"]
      weather = data["weather"]
      temp = data["temperature_string"]
      humidity = data["relative_humidity"]
      dewpoint = data["dewpoint_string"]
    rescue StandardError => e
      @irc.privmsg @client_sid, @config["debug-channels"]["bot"], "[ERROR] #{__method__.to_s}: #{e.message}"
      return "An unexpected error has occured. The developers have been notified."
    end

    array.push("#{lastupdated} - #{location} - Temp: #{temp} - Info: #{weather} - Winds: #{wind} - Humidity: #{humidity} - Dewpoint: #{dewpoint}")
    array.push(description.gsub("\n", ' ')[1..-2])
    return array
  end

  def handle_privmsg hash, flags
    return if !((flags & Flags::Weather) > 0)
    target = hash["target"]
    target = hash["from"] if hash["target"] == @client_sid

    return if !target.include?("#")

    if ["!weather", "!w"].include? hash["command"].downcase
      run(hash["parameters"]).each do |line|
        @irc.privmsg @client_sid, target, line if line
      end
    end

  end

  def init e, m, c, d
    @e = e
    @m = m
    @c = c
    @d = d

    @w_api = Wunderground.new("d58c72fb57de4a46")

    @config = @c.Get
    @parameters = @config["connections"]["clients"]["irc"]["parameters"]
    @client_sid = "#{@parameters["sid"]}000003"
    @initialized = false

    @e.on_event do |type, hash, flags|
      if type == "Bot-Chat"
        if !@initialized
          @config = @c.Get
          @irc = IRCLib.new hash["name"], hash["sock"]
          @initialized = true
        end
        handle_privmsg hash, flags if hash["msgtype"] == "PRIVMSG"
      end
    end
  end
end
