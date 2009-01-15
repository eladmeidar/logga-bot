# Controller for the logga leaf.

class Controller < Autumn::Leaf
  
  before_filter :check_for_new_day
      
  def who_command(stem, sender, reply_to, msg)
    if authorized?(sender[:nick])
      person = Person.find_by_name(msg.strip)
      if person
        stem.message("#{msg}: thanked #{person.votes.positive.count} time(s), rebuked #{person.votes.negative.count} time(s)", sender[:nick])
        stem.message("#{msg}: #{person.hostnames.count} hostnames(s)", sender[:nick])
#        stem.message("#{msg}: #{person.recent_chat_count} recent messages(s), #{} ", sender[:nick])
        unless person.notes.blank?
          stem.message("Notes for #{msg}: #{person.notes}", sender[:nick])
        end
      end
    end
  end

  def gitlog_command(stem, sender, reply_to, msg)
    `git log -1`.split("\n").first
  end

  def tip_command(stem, sender, reply_to, command, options={})
    return unless authorized?(sender[:nick])
    if tip = Tip.find_by_command(command.strip) 
      tip.text.gsub!("{nick}", sender[:nick])
      message = tip.text
      message = "#{options[:directed_at]}: #{message}" if options[:directed_at]
      find_or_create_person("logga").chats.create(:channel => reply_to, :message => message, :message_type => "message")
      stem.message(message, reply_to)          
    else
      stem.message("I could not find that command. If you really want that command, go to http://rails.loglibrary.com/tips/new?command=#{command} and create it!", sender[:nick])
    end    
  end
  
  def join_command(stem, sender, reply_to, msg)
    join_channel(msg) if authorized?(sender[:nick])
  end

  def part_command(stem, sender, reply_to, msg)
    leave_channel(msg) if authorized?(sender[:nick])
  end
  
  def help_command(stem, sender, reply_to, msg)
    if authorized?(sender[:nick])
      if msg.nil?
        stem.message("A list of all commands can be found at http://rails.loglibrary.com/tips", sender[:nick])
      else
        comnand = msg.split(" ")[1]
        if tip = Tip.find_by_command(command)
          stem.message(" #{tip.command}: #{tip.description} - #{tip.text}", sender[:nick])
        else  
          stem.message("I could not find that command. If you really want that command, go to http://rails.loglibrary.com/tips/new?command=#{command} and create it!", sender[:nick])
        end
      end
    end
  end
  
  def update_api_command(stem, sender, reply_to, msg)
    return unless authorized?(sender[:nick])
    require 'hpricot'
    require 'net/http'
    stem.message("Updating API index", sender[:nick])
    Constant.delete_all
    Entry.delete_all
    # Ruby on Rails Methods
    update_api("Rails", "http://api.rubyonrails.org")
    update_api("Ruby", "http://www.ruby-doc.org/core")
    
    stem.message("Updated API index! Use the !lookup <method> or !lookup <class> <method> to find what you're after", sender[:nick])
    return nil
  end
  
  def lookup_command(stem, sender, reply_to, msg, opts={})
    return if msg.blank?
      parts = msg.split(" ") if msg.include?(" ")
      parts ||= msg.split("#") if msg.include?("#")
      parts ||= msg.gsub(/\(.*?\)/,'').split(".") if msg.include?(".")
      parts ||= [msg]
      @parts = parts
      @sender = sender
      @stem = stem
      @reply_to = reply_to
    
    # Is the first word a constant?
    if /^[A-Z]/.match(parts.first)
      constant = Constant.find_by_name(parts.first)
      constant ||= Constant.find_by_name(parts.first + "::ClassMethods")
      if constant
        entry = constant.entries.find_by_name(parts.last)
        if entry
          constant.increment!("count")
          entry.increment!("count")
          message = "#{constant.name}##{entry.name}: #{entry.url}"
          message = send_lookup_message(stem, message, reply_to, opts[:directed_at])
        else
          if parts.last != parts.first
            entries = Entry.find_all_by_name(parts.last)
            if entries.empty?
              stem.message("Could not find any entry with the name #{parts.last} anywhere in the API.", sender[:nick])
            else
              classes_for(entries)
            end
          else
            constant.increment!("count")
            message = "#{constant.name}: #{constant.url}"
            send_lookup_message(stem, message, reply_to, opts[:directed_at])
          end
        end      
      # When they specify an invalid constant (perhaps a partial name) and a valid entry.
      elsif parts.first != parts.last
        entries = Entry.find_all_by_name(parts.last)
        classes_for(entries)
      # When they specify an invalid constant AND an invalid entry.
      else
        stem.message("Could not find constant #{parts.first} or #{parts.first}::ClassMethods in the API!", sender[:nick])
      end
    else
      # The first word is a method then
      entries = Entry.find_all_by_name(parts.first)
      if entries.size == 1
        entry = entries.first  
        constant = entry.constant
        constant.increment!("count")
        entry.increment!("count")
        message = "#{constant.name}##{entry.name}: #{entry.url}"
        message = send_lookup_message(stem, message, reply_to, opts[:directed_at])
      elsif entries.size > 1
        classes_for(entries) 

      else
        stem.message("Could not find any entry with the name #{parts.last} anywhere in the API.", sender[:nick])
      end
    end
  end
  
  def google_command(stem, sender, reply_to, msg, opts={})
    google("http://www.google.com/search", stem, sender, msg, reply_to, opts)
  end
  
  alias :g_command :google_command 
  
  def gg_command(stem, sender, reply_to, msg, opts={})
    google("http://www.letmegooglethatforyou.com/", stem, sender, msg, reply_to, opts)
  end
  
  private
  
  # Lookup stuff
  
  def send_lookup_message(stem, message, reply_to, directed_at=nil)
    message = "#{directed_at}: " + message  if directed_at
    stem.message(message, reply_to)  
  end
  
  def update_api(name, url)
    Api.find_or_create_by_name_and_url(name, url)
    update_methods(Hpricot(Net::HTTP.get(URI.parse("#{url}/fr_method_index.html"))), url)
    update_classes(Hpricot(Net::HTTP.get(URI.parse("#{url}/fr_class_index.html"))), url)
  end
  
  def update_methods(doc, prefix)
    doc.search("a").each do |a|
      names = a.inner_html.split(" ")
      method = names[0]
      name = names[1].gsub(/[\(|\)]/, "")
      # The same constant can be defined twice in different APIs, be wary!
      url = prefix + "/classes/" + name.gsub("::", "/") + ".html"
      constant = Constant.find_or_create_by_name_and_url(name, url)
      constant.entries.create!(:name => method, :url => prefix + "/" + a["href"])
    end
  end
  
  def update_classes(doc, prefix)
    doc.search("a").each do |a|
      constant = Constant.find_or_create_by_name_and_url(a.inner_html, a["href"])
    end
  end
  
  # Ye olde Google.
  
  def google(host, stem, sender, msg, reply_to, opts)
    return unless authorized?(sender[:nick])
    message = "#{host}?q=#{msg.split(" ").join("+")}"
    if opts[:directed_at]
      message = opts[:directed_at] + ": #{message}" 
      stem.message(message)
    else
      return message
    end
  end
  
  # I, Robot.
  
  def i_am_a_bot
    ["I am a bot! Please do not direct messages at me!",
     "FYI I am a bot.",
     "Please go away. I'm only a bot.",
     "I am not a real person.",
     "No I can't help you.",
     "Wasn't it obvious I was a bot?",
     "I am not a werewolf; I am a bot.",
     "I'm botlicious.",
     "Congratulations! You've managed to message a bot.",
     "I am a bot. Your next greatest discovery will be that the sky is, in fact, blue."     
     ].rand
  end
  
  # Who's there?
  
  def authorized?(nick)
    User.find_by_login(nick.downcase)
  end

  def check_for_new_day_filter
    @day = Day.find_or_create_by_date(Date.today) if @today!=Date.today
    @today = Date.today
    @day.increment!("chats_count")
  end

  def find_or_create_person(name)
    Person.find_or_create_by_name(name)
  end

  def find_or_create_hostname(hostname, person)
    person.hostnames << Hostname.find_or_create_by_hostname(hostname)
  end

  def did_receive_channel_message(stem, sender, channel, message) 
     person = find_or_create_person(sender[:nick])
     # Does this message clearly reference another person as the first word.
     other_person = /^(.*?)[:|,]/.match(message)
     other_person = Person.find_by_name(other_person[1]) unless other_person.nil?
     # try to match a non-existent command which might be a tip
     if m = /^(([^:]+):)?\s?!([^\s]+)\s?(.*)?/.match(message)
       cmd_sym = "#{m[3]}_command".to_sym
       # if we don't respond to this command then it's likely a tip
       if respond_to?(cmd_sym)
         if !m[2].nil?
           send(cmd_sym, stem, sender, channel, m[4], { :directed_at => m[2] })
         end
       else
         tip_command(stem,sender,channel,m[3], { :directed_at => m[2] })
       end
     end
     
     # Don't speak to me!
     if message.match(/^logga[:|,]/)
       stem.message(i_am_a_bot, sender[:nick])
     end

     # Log Chat Line
     chat = person.chats.create(:channel => channel, :message => message, :message_type => "message", :other_person => other_person)

     ## Did the person thank another person?
     # Someone was called "a"
     words = message.split(" ") - ["a"]
     people = []
     for word in words
       word = word.gsub(":", "")
       word = word.gsub(",", "")
       # Can't be thanked if count < 100...
       # stops stuff like "why thanks Radar" coming up for chatter "why" & "Radar" instead of just "Radar"
       people << Person.find_by_name(word, :conditions => "chats_count > 100")
     end

     # Allow voting for multiple people.
     people = people.compact!
     if /(thank|thx|props|kudos|big ups|10x|cheers)/i.match(chat.message) && chat.message.split(" ").size != 1 && !people.blank?
       for person in (people - [chat.person] - ["anathematic"])
         person.votes.create(:chat => chat, :person => chat.person)
       end
     end
   end

   def someone_did_join_channel(stem, sender, channel)
     person = find_or_create_person(sender[:nick])
     find_or_create_hostname(sender[:host], person)
     person.chats.create(:channel => channel, :message_type => "join")  unless person[:nick] == "logga"
   end

   def someone_did_leave_channel(stem, sender, channel)
     person = find_or_create_person(sender[:nick])
     find_or_create_hostname(sender[:host], person)
     person.chats.create(:channel => channel, :message_type => "part")
   end

   def someone_did_quit(stem, sender, message)
     person = find_or_create_person(sender[:nick])
     find_or_create_hostname(sender[:host], person)
     person.chats.create(:channel => nil, :message => message, :message_type => "quit")
   end

   def nick_did_change(stem, person, nick)
     old_person = person
     person = find_or_create_person(person[:nick])
     other_person = find_or_create_person(nick)
     find_or_create_hostname(old_person[:host], person)
     find_or_create_hostname(old_person[:host], other_person)
     person.chats.create(:channel => nil, :person => person, :message_type => "nick-change", :other_person => other_person)
   end

   def someone_did_kick(stem, kicker, channel, victim, message)
     person = find_or_create_person(kicker[:nick])
     find_or_create_hostname(kicker[:host], person)
     other_person = find_or_create_person(victim)
     person.chats.create(:channel => channel, :other_person => other_person, :message => message, :message_type => "kick")
   end

   def someone_did_change_topic(stem, person, channel, topic)
     person = find_or_create_person(person[:nick])
     person.chats.create(:channel => channel, :message => topic, :message_type => "topic")
   end

   def someone_did_gain_privilege(stem, channel, nick, privilege, bestower)
     person = find_or_create_person(nick)
     other_person = find_or_create_person(bestower[:nick])
     person.chats.create(:channel => channel, :message => privilege.to_s, :other_person => other_person, :message_type => "gained_privilege")
   end

   def someone_did_lose_privilege(stem, channel, nick, privilege, bestower)
     person = find_or_create_person(nick)
     other_person = find_or_create_person(bestower[:nick])
     person.chats.create(:channel => channel, :message => privilege.to_s, :other_person => other_person, :message_type => "lost_privilege")
   end

   def channel_did_gain_property(stem, channel, property, argument, bestower)
     person = find_or_create_person(bestower[:nick])
     person.chats.create(:channel => channel, :message => "#{argument[:mode]} #{argument[:parameter]}", :message_type => "mode")
   end
 
  alias_method :channel_did_lose_property, :channel_did_gain_property
  
    
end
