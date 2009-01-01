class Person < ActiveRecord::Base
  has_many :chats
  has_many :other_chats, :class_name => "Chat", :foreign_key => "other_person_id"
  has_many :votes, :foreign_key => "other_person_id"
  has_many :thanks, :class_name => "Vote", :foreign_key => "person_id"
  has_and_belongs_to_many :hostnames, :uniq => true
  
  def to_param
    name
  end
  
  alias_method :to_s, :to_param
end