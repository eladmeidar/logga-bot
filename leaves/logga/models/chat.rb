class Chat < ActiveRecord::Base
  
  belongs_to :person, :counter_cache => true
  belongs_to :other_person, :class_name => "Person"
end
