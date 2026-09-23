# frozen_string_literal: true

class CreateMultirdpGrants < ActiveRecord::Migration[7.2]
  def change
    create_table :multirdp_grants do |t|
      t.integer :license_id, null: false
      t.integer :user_id, null: false
      t.string  :status, null: false, default: 'active'
      t.date    :valid_until
      # Einstellungen des Benutzers als JSON.
      t.text    :settings, limit: 16.megabytes
      t.integer :settings_revision, null: false, default: 0
      # WireGuard-Konfigurationen, verschlüsselt (ActiveRecord::Encryption).
      t.text    :secrets, limit: 16.megabytes
      t.timestamps null: false
    end
    add_index :multirdp_grants, [:license_id, :user_id], unique: true
    add_index :multirdp_grants, :user_id
    add_index :multirdp_grants, :status
  end
end
