class DropPlatformPermissionTables < ActiveRecord::Migration
  # Run this one *after* the deploy that stops reading these tables, not in the same step.
  #
  # 20261113120000 creates platform_scopes and platform_application_scopes; the code switches to
  # Platform::Scope and Platform::ApplicationScope in the same release.  Dropping the old tables
  # in that release would mean a window where running code still refers to them -- an old
  # application process during a rolling deploy, a console someone left open, a background job
  # that started before the restart.  Separating the drop keeps the rollback cheap: until this
  # migration runs, reverting the deploy needs nothing but the previous code.
  #
  # Both tables are expected to be empty by now.  platform_permissions held two rows in
  # production, sendgrid_callback and skip_exception_logging, which were capability flags rather
  # than scopes and are now listed in Platform::Application.permissions; delete them before
  # running this, or let the drop take them.  platform_application_permissions was already empty.
  #
  # #down recreates the structure but not the contents, which is the honest thing a down can do
  # here: the rows it would need are not derivable from anything that remains.
  def self.up
    drop_table :platform_application_permissions
    drop_table :platform_permissions
  end

  def self.down
    create_table :platform_permissions do |t|
      t.string    :keyword,     :null => false
      t.text      :description, :null => false
      t.timestamps
      t.integer   :icon_id,     :limit => 8
      t.integer   :level
      t.integer   :position
      t.string    :headline
    end

    add_index :platform_permissions, [:keyword], :name => 'index_platform_permissions_on_keyword'

    create_table :platform_application_permissions do |t|
      t.integer   :application_id
      t.integer   :permission_id
      t.timestamps
    end

    add_index :platform_application_permissions, [:application_id],
              :name => 'index_platform_application_permissions_on_application_id'
  end
end
