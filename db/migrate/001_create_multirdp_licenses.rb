# frozen_string_literal: true

class CreateMultirdpLicenses < ActiveRecord::Migration[7.2]
  def change
    create_table :multirdp_licenses do |t|
      t.string  :kind, null: false, default: 'multirdp'
      t.string  :name, null: false
      t.text    :notes
      # Vorgabe des Administrators als JSON (Server, RemoteApps mit Symbolen).
      t.text    :data, limit: 16.megabytes
      t.integer :revision, null: false, default: 1
      t.integer :grace_days, null: false, default: 14
      t.integer :created_by_id
      t.timestamps null: false
    end
    add_index :multirdp_licenses, :kind
    add_index :multirdp_licenses, :created_by_id
  end
end
