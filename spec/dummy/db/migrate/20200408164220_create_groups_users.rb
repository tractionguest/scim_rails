class CreateGroupsUsers < ActiveRecord::Migration[6.0]
  def change
    create_table :groups_users do |t|
      t.references :user, index: true
      t.references :group, index: true

      t.timestamps null: false
    end
  end
end
