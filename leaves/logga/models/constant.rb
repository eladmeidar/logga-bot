class Constant < ActiveRecord::Base
  has_many :entries
  belongs_to :namespace
  validates_presence_of :name
  
  def to_s
    "#{name}: #{url}"
  end
end
