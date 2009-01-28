class Entry < ActiveRecord::Base
  belongs_to :constant
  validates_presence_of :name, :url
  
  def to_s
    "#{with_constant}: #{url}"
  end
  
  def with_constant
    "#{constant.name}##{name}"
  end
  
  
end
