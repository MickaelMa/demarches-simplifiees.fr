# == Schema Information
#
# Table name: archives
#
#  id           :bigint           not null, primary key
#  content_type :string
#  month        :datetime
#  status       :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
class Archive < ApplicationRecord
  include AASM

  MAX_DUREE_CONSERVATION_ARCHIVE = 1.week

  has_and_belongs_to_many :groupe_instructeurs

  has_one_attached :file

  scope :stale, -> { where('updated_at < ?', (Time.zone.now - MAX_DUREE_CONSERVATION_ARCHIVE)) }

  enum content_type: {
    everything: 'everything',
    monthly:    'monthly'
  }

  enum status: {
    pending: 'pending',
    generated: 'generated'
  }

  aasm whiny_persistence: true, column: :status, enum: true do
    state :pending, initial: true
    state :generated

    event :make_available do
      transitions from: :pending, to: :generated
    end
  end

  def available?
    status == 'generated' && file.attached?
  end
end