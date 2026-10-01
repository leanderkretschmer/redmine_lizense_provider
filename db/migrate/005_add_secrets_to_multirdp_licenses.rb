# frozen_string_literal: true

class AddSecretsToMultirdpLicenses < ActiveRecord::Migration[7.2]
  def change
    # RDP-Kennwörter je Server, verschlüsselt (ActiveRecord::Encryption).
    add_column :multirdp_licenses, :secrets, :text, limit: 16.megabytes
  end
end
