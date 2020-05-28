class User < ApplicationRecord
  belongs_to :company

  before_save :generate_uuid

  has_many :groups_users
  has_many :groups, through: :groups_users

  validates \
    :first_name,
    :last_name,
    :email,
    presence: true

  validates \
    :email,
    uniqueness: {
      case_insensitive: true
    }

  def active?
    archived_at.blank?
  end

  def archived?
    archived_at.present?
  end

  def archive!
    write_attribute(:archived_at, Time.now)
    save!
  end

  def unarchived?
    archived_at.blank?
  end

  def unarchive!
    write_attribute(:archived_at, nil)
    save!
  end

  private

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
