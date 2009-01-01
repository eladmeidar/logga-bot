class Vote < ActiveRecord::Base
  belongs_to :person
  belongs_to :other_person, :class_name => "Person"
  belongs_to :chat
  
  named_scope :positive, :conditions => ["positive = ?", true]
  named_scope :negative, :conditions => ["positive = ?", false]
end
