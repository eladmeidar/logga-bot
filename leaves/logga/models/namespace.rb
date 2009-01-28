class Namespace < ActiveRecord::Base
  belongs_to :api
  has_many :constants
end