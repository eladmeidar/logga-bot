class Entry < ActiveRecord::Base
  belongs_to :constant
  validates_presence_of :name, :url
end
