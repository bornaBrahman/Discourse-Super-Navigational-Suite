# frozen_string_literal: true

class CreateSuperNavigationProfiles < ActiveRecord::Migration::Current
  def change
    create_table :super_navigation_profiles do |t|
      t.string :name, null: false
      t.string :profile_key, null: false
      t.text :config_json, null: false
      t.boolean :active, null: false, default: false
      t.integer :created_by_id
      t.timestamps
    end

    add_index :super_navigation_profiles, :profile_key, unique: true
    add_index :super_navigation_profiles, :active
  end
end
