# == Schema Information
#
# Table name: users
#
#  id         :integer          not null, primary key
#  email      :string
#  gender     :string
#  link       :string
#  locale     :string
#  mugshot    :string
#  name       :string
#  password   :string
#  created_at :datetime
#  updated_at :datetime
#
# Indexes
#
#  index_users_on_email               (email)
#  index_users_on_email_and_password  (email,password)
#
class User < ApplicationRecord

  def gender
    super || 'unknown'
  end

  def guest?
    name == 'Guest'
  end

  def admin?
    name == 'Admin'
  end

  def developer?
    name == 'Developer'
  end

  def to_s
    name
  end

  def self.authenticate(name, password)
    find_by_name_and_password(name, password)
  end

end # class User
