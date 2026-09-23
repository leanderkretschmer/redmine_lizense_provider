# frozen_string_literal: true

class CreateMultirdpEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :multirdp_events do |t|
      t.integer  :grant_id
      t.integer  :device_id
      t.integer  :user_id
      t.string   :action, null: false
      t.text     :detail
      t.string   :ip
      t.datetime :created_at, null: false
    end
    add_index :multirdp_events, :grant_id
    add_index :multirdp_events, :device_id
    add_index :multirdp_events, :user_id
    add_index :multirdp_events, [:action, :ip, :created_at], name: 'index_multirdp_events_on_action_ip_created'
  end
end
