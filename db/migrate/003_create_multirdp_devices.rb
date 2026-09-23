# frozen_string_literal: true

class CreateMultirdpDevices < ActiveRecord::Migration[7.2]
  def change
    create_table :multirdp_devices do |t|
      t.integer  :grant_id, null: false
      # Nur der SHA-256-Hash des Gerätetokens.
      t.string   :token_digest, null: false, limit: 64
      t.string   :name
      t.string   :platform
      t.string   :app_version
      t.string   :status, null: false, default: 'pending'
      # Vorbereitung für Weg B (Schlüsselpaar je Gerät): öffentlicher WireGuard-Schlüssel.
      t.string   :public_key
      t.datetime :requested_at
      t.datetime :approved_at
      t.datetime :last_seen_at
      t.string   :requested_ip
      t.string   :last_seen_ip
      t.timestamps null: false
    end
    add_index :multirdp_devices, :token_digest, unique: true
    add_index :multirdp_devices, :grant_id
    add_index :multirdp_devices, :status
  end
end
