class CreateGroups < ActiveRecord::Migration[4.2]
  def change
    create_table :groups do |t|
      t.string :display_name, null: false
      t.string :email, null: false
      t.boolean :random_attribute, default: false
      t.string :uuid, null: false

      t.integer :company_id

      t.timestamp :archived_at

      t.timestamps null: false
    end
  end
end
