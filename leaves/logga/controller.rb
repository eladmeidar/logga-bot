# Controller for the logga leaf.

class Controller < Autumn::Leaf
  
  before_filter :check_for_new_day
  
  def did_start_up
    @classes = File.readlines("leaves/logga/classes").map { |line| line.split(" ")}
    @methods = File.readlines("leaves/logga/methods").map { |line| line.split(" ")}
  end
      
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
      constant = Constant.find_or_create_by_name_and_url(a.inner_html, prefix + "/" + a["href"])
    end
  end
  
  def lookup_command(stem, sender, reply_to, msg, opts={})
    msg = msg.split(" ")[0..-1].map { |a| a.split("#") }.flatten!
    # It's a constant! Oh... and there's nothing else in the string!
    if /^[A-Z]/.match(msg.first) && msg.size == 1
     object = find_constant(stem, sender, reply_to, msg.first, nil, opts)
     # It's a method!
     else
       # Right, so they only specified one argument. Therefore, we look everywhere.
       if msg.first == msg.last
         object = find_method(stem, sender, reply_to, msg, nil, opts)
       # Left, so they specified two arguments. First is probably a constant, so let's find that!
       else
         object = find_method(stem, sender, reply_to, msg.last, msg.first, opts)
       end  
    end 
  end
  
  def for_sql(string)
    string
  end
  
  
  def find_constant(stem, sender, reply_to, name, entry=nil, opts={})
    # Find by specific name.
    constants = Constant.find_all_by_name(name, :include => "entries")
    # Find by name beginning with <blah>.
    constants = Constant.all(:conditions => ["name LIKE ?", name + "%"], :include => "entries") if constants.empty?
    # Find by fuzzy.
    constants = Constant.find_by_sql("select * from constants where name LIKE '%#{for_sql(name.split("").join("%"))}%'") if constants.empty?
    if constants.size > 1
      # Narrow it down to the constants that only contain the entry we are looking for.
      if !entry.nil?
        constants = constants.select { |constant| !constant.entries.find_by_name(entry).nil? }
        return [constants, constants.size]
      else
        display_constants(stem, sender, reply_to, constants, opts={})
      end
      if constants.size == 1
        if entry.nil?
          stem.message("#{opts[:directed_at] ? opts[:directed_at] + ":"  : ''} #{constant}")
        else
          return [[constants.first], 1]
        end
      elsif constants.size == 0
        if entry
          stem.message("There are no constants that match #{name} and contain #{entry}.", reply_to)
        else
          stem.message("There are no constants that match #{name}", reply_to)
        end
      else
        return [constants, constants.size]
      end
    else
      if entry.nil?
       display_constants(stem, sender, reply_to, constants, opts={})
      else
        return [[constants.first], 1]
      end
    end
  end  

  # Find an entry.
  # If the constant argument is passed, look it up within the scope of the constant.
  def find_method(stem, sender, reply_to, name, constant=nil, opts={})  
    if constant
      constants, number = find_constant(stem, sender, reply_to, constant, name)
    end
    methods = [] 
    methods = Entry.find_all_by_name(name.to_s)
    methods = Entry.all(:conditions => ["name LIKE ?", name.to_s + "%"]) if methods.empty?
    methods = Entry.find_by_sql("select * from entries where name LIKE '%#{for_sql(name.split("").join("%"))}%'") if methods.empty?
    
    if constant
      methods = methods.select { |m| constants.include?(m.constant) }
    end
    count = 0
    if methods.size == 1
      method = methods.first
      stem.message("#{opts[:directed_at] ? opts[:directed_at] + ":"  : ''} (#{method.constant.name}) #{method.name} #{method.url}", reply_to)
    elsif methods.size <= 3
      for method in methods
        stem.message("#{opts[:directed_at] ? opts[:directed_at] + ":"  : ''} #{count += 1}. (#{method.constant.name}) #{method.name} #{method.url}", reply_to)
      end
      methods
    else
      stem.message("#{sender[:nick]}: Please be more specific.", reply_to)
    end
    return nil
  end
  
  def display_constants(stem, sender, reply_to, constants, opts={})
    count = 0
    if constants.size == 1
      constant = constants.first
      message = "#{opts[:directed_at] ? opts[:directed_at] + ":"  : ''} #{constant.name} #{constant.url}"
      stem.message(message, reply_to)
    elsif constants.size <= 3
      for constant in constants
        message = "#{opts[:directed_at] ? opts[:directed_at] + ":"  : ''} #{count+=1}. #{constant.name} #{constant.url}"
        stem.message(message, reply_to)
      end
    else
      stem.message("#{sender[:nick]}: Please refine your query, we found #{constants.size} constants (threshold is 3).", reply_to)
    end
    return nil
  end
  
  
  def google_command(stem, sender, reply_to, msg, opts={})
    search("http://www.google.com/search", stem, sender, msg, reply_to, opts)
  end
  
  alias :g_command :google_command 
  
  def gg_command(stem, sender, reply_to, msg, opts={})
    search("http://www.letmegooglethatforyou.com/", stem, sender, msg, reply_to, opts)
  end
  
  def railscast_command(stem, sender, reply_to, msg, opts={})
    search("http://railscasts.com/episodes", stem, sender, msg, reply_to, opts, "search")
  end
  
  def githubs_command(stem, sender, reply_to, msg, opts={})
    search("http://github.com/search", stem, sender, msg, reply_to, opts)
  end
  
  def github_command(stem, sender, reply_to, msg, opts={})
    parts = msg.split(" ")
    message = "http://github.com/#{parts[0]}/#{parts[1]}/tree/#{parts[2].nil? ? 'master' : parts[2]}"
    message += "/#{parts[3..-1].join("/")}" if !parts[3].nil?
    direct_at(stem, reply_to, message, opts[:directed_at])
  end
  
  private
  
  def direct_at(stem, reply_to, message, who=nil)
    if who
      message = who + ": #{message}" 
      stem.message(message, reply_to)
    else
      return message
    end
  end
  
  def search(host, stem, sender, msg, reply_to, opts, query_parameter="q")
    message = "#{host}?#{query_parameter}=#{msg.split(" ").join("+")}"
    direct_at(stem, reply_to, message, opts[:directed_at])
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

  def check_for_new_day_filter(host, stem, sender, msg, reply_to, opts)
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
     return if sender.nil?
     person = find_or_create_person(sender[:nick])
     find_or_create_hostname(sender[:host], person)
     person.chats.create(:channel => channel, :message_type => "join")  unless sender[:nick] == "logga"
   end

   def someone_did_leave_channel(stem, sender, channel)
     person = find_or_create_person(sender[:nick])
     find_or_create_hostname(sender[:host], person)
     person.chats.create(:channel => channel, :message_type => "part")
   end

   def someone_did_quit(stem, sender, message)
     return if sender.nil?
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
