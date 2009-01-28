#!/usr/bin/ruby
LIB_DIR = File.dirname(__FILE__)

CLASSES = File.join(LIB_DIR, "classes")
METHODS = File.join(LIB_DIR, "methods")
DECENT_OPERATING_SYSTEM = RUBY_PLATFORM =~ /darwin/

require File.join(LIB_DIR, "config")

# Updates blazingly fast now.
def update
  puts "UPDATING..."
  f = File.open(CLASSES, "w+")
  f.close
  f = File.open(METHODS, "w+")
  f.close
  update_api("http://api.rubyonrails.org/")
  update_api("http://ruby-doc.org/core/")
end

def update_api(url)
  update_classes(url)
  update_methods(url)
end

def update_classes(url)
  c = File.open(CLASSES,"a+")
  classes = File.readlines(CLASSES)
  doc = Hpricot(Net::HTTP.get(URI.parse("#{url}/fr_class_index.html")))
  doc.search("a").each do |a|
    puts "#{a.inner_html}"
    c.write "#{a.inner_html} #{url + a['href']}\n" if !classes.include?(a.inner_html)
  end
end

def update_methods(url)
  c = File.open(CLASSES, "a+")
  classes = File.readlines(CLASSES)
  e = File.open(METHODS, "a+")
  methods = File.readlines(METHODS)
  doc = Hpricot(Net::HTTP.get(URI.parse("#{url}/fr_method_index.html")))
  doc.search("a").each do |a|
    constant_name = a.inner_html.split(" ")[1].gsub(/[\(|\)]/, "")
    if /^[A-Z]/.match(constant_name)
      e.write "#{a.inner_html} #{url + a['href']}\n"
    end
  end
end


   
 
 def lookup
   @classes = File.readlines(CLASSES).map { |line| line.split(" ")}
   @methods = File.readlines(METHODS).map { |line| line.split(" ")}
   parts = ARGV[0..-1].map { |a| a.split("#") }.flatten!
   
   # It's a constant! Oh... and there's nothing else in the string!
   if /^[A-Z]/.match(parts.first) && parts.size == 1
    object = find_constant(parts.first)
    # It's a method!
    else
      # Right, so they only specified one argument. Therefore, we look everywhere.
      if parts.first == parts.last
        object = find_method(parts.first)
      # Left, so they specified two arguments. First is probably a constant, so let's find that!
      else
        object = find_method(parts.last, parts.first)
      end  
   end 
 end
 lookup