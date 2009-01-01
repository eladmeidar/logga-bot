# Class is already taken!
class Constant < ActiveRecord::Base
  has_many :entries
  validates_presence_of :name
end
