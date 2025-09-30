class CreateTestUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string  :name
      t.string  :gender
      t.string  :email
      t.string  :password
      t.string  :mugshot
      t.string  :link
      t.string  :locale
      t.timestamps
    end
    add_index :users, [:email]
    add_index :users, [:email, :password]
  end
end
