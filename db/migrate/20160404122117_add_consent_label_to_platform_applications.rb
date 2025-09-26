class AddConsentLabelToPlatformApplications < ActiveRecord::Migration[4.2]
  def self.up
    add_column :platform_applications, :consent_label, :text
  end

  def self.down
    remove_column :platform_applications, :consent_label
  end
end
