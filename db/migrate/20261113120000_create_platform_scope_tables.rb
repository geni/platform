class CreatePlatformScopeTables < ActiveRecord::Migration
  # OAuth scopes, under their own name at last.
  #
  # These replace platform_permissions and platform_application_permissions, which held two
  # unrelated things under one word.  A "permission" in this system was either an OAuth scope the
  # user consents to on the authorize screen (user_basic, user_email, family_basic, tree_basic --
  # the level 0 rows, carrying end-user copy like "Access my basic information") or an operational
  # capability flag an admin grants to an application (no_rate_limit, grant_type_password,
  # allow_iframe -- the level 1000 rows).  Sharing a table meant sharing a namespace, and
  # Platform::Application#granted_scope intersected a requested OAuth scope against whichever
  # keywords happened to be in it.
  #
  # Capability flags do not move here.  They stay where they already are and already work: the
  # comma-separated platform_applications.permissions column, read through
  # Platform::SimpleStringPermissions#has_permission?, with the grantable list in
  # Platform::Application.permissions.  Only scopes live in these tables.
  #
  # No level column, by consequence: it existed only to tell the two kinds apart, and there is
  # nothing left to tell apart.
  #
  # Nothing is copied across.  platform_permissions held exactly two rows in production --
  # sendgrid_callback and skip_exception_logging, both capability flags, both with level NULL --
  # and both are now named in Platform::Application.permissions instead, which is where a flag
  # belongs.  The join table was empty.
  def self.up
    create_table :platform_scopes do |t|
      t.string    :keyword,     :null => false
      t.text      :description, :null => false
      t.string    :headline
      t.integer   :icon_id,     :limit => 8
      t.integer   :position
      t.timestamps
    end

    add_index :platform_scopes, [:keyword], :name => 'index_platform_scopes_on_keyword'

    create_table :platform_application_scopes do |t|
      t.integer   :application_id
      t.integer   :scope_id
      t.timestamps
    end

    add_index :platform_application_scopes, [:application_id],
              :name => 'index_platform_application_scopes_on_application_id'
    add_index :platform_application_scopes, [:scope_id],
              :name => 'index_platform_application_scopes_on_scope_id'
  end

  def self.down
    drop_table :platform_application_scopes
    drop_table :platform_scopes
  end
end
