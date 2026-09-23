# frozen_string_literal: true

# Zuteilung einer Lizenz an einen Benutzer. Trägt die Einstellungen des
# Benutzers (`settings`) und die verschlüsselten WireGuard-Konfigurationen.
class MultirdpGrant < ActiveRecord::Base
  STATUS_ACTIVE    = 'active'
  STATUS_SUSPENDED = 'suspended'
  STATUS_REVOKED   = 'revoked'
  STATUSES = [STATUS_ACTIVE, STATUS_SUSPENDED, STATUS_REVOKED].freeze

  # Zustand "abgelaufen" ist abgeleitet, keine Spalte.
  EFFECTIVE_EXPIRED = 'expired'

  belongs_to :license, class_name: 'MultirdpLicense', inverse_of: :grants
  belongs_to :user
  has_many :devices, class_name: 'MultirdpDevice', foreign_key: :grant_id, dependent: :destroy, inverse_of: :grant
  has_many :events, class_name: 'MultirdpEvent', foreign_key: :grant_id, dependent: :nullify

  serialize :settings, coder: JSON
  # Verschlüsselt in der Datenbank; enthält ein JSON-Objekt server_id => {config, updated_at}.
  encrypts :secrets

  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :license_id }
  validate :single_active_grant_per_user

  scope :sorted, -> { joins(:user).order('users.lastname, users.firstname, users.login') }
  scope :for_user, ->(user) { where(user_id: user.is_a?(User) ? user.id : user) }
  scope :of_kind, ->(kind) { joins(:license).where(multirdp_licenses: { kind: kind }) }
  scope :status_active, -> { where(status: STATUS_ACTIVE) }
  scope :not_expired, -> { where('multirdp_grants.valid_until IS NULL OR multirdp_grants.valid_until >= ?', User.current.today) }

  # Die eine wirksame multiRDP-Zuteilung eines Benutzers (oder nil).
  def self.effective_for(user)
    for_user(user).of_kind(MultirdpLicenses::KIND_MULTIRDP).status_active.not_expired
                  .order(:created_at).first
  end

  def settings
    value = super
    value.is_a?(Hash) ? value : MultirdpLicenses::DataSchema.empty_settings
  end

  def expired?
    valid_until.present? && valid_until < User.current.today
  end

  # active / suspended / revoked / expired
  def effective_status
    return EFFECTIVE_EXPIRED if status == STATUS_ACTIVE && expired?

    status
  end

  def effectively_active?
    effective_status == STATUS_ACTIVE
  end

  def status_label
    ::I18n.t(:"label_multirdp_grant_status_#{effective_status}", default: effective_status)
  end

  # Grund für den Client (Abschnitt 6): entzogen / abgelaufen.
  # "suspended" wird ebenfalls als "entzogen" gemeldet (siehe README).
  def denial_reason
    case effective_status
    when EFFECTIVE_EXPIRED then 'abgelaufen'
    when STATUS_ACTIVE     then nil
    else 'entzogen'
    end
  end

  # ---- Einstellungen des Benutzers --------------------------------------

  # Schreibt neue Einstellungen und erhöht settings_revision. Gibt false
  # zurück, wenn die erwartete Fassung nicht mit der gespeicherten übereinstimmt.
  def write_settings!(new_settings, expected_revision)
    with_lock do
      return false unless expected_revision.to_i == settings_revision

      self.settings = new_settings
      self.settings_revision = settings_revision + 1
      save!
    end
    true
  end

  # ---- WireGuard-Konfigurationen ----------------------------------------

  def secrets_hash
    return {} unless MultirdpLicenses::Encryption.ready?

    parsed = secrets.present? ? JSON.parse(secrets) : {}
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError, ActiveRecord::Encryption::Errors::Base
    {}
  end

  # Server, für die eine WireGuard-Konfiguration vorliegt.
  def secret_server_ids
    secrets_hash.select { |_, e| e.is_a?(Hash) && e['config'].present? }.keys
  end

  # Server, für die ein RDP-Kennwort vorliegt.
  def rdp_password_server_ids
    secrets_hash.select { |_, e| e.is_a?(Hash) && e['rdp_password'].present? }.keys
  end

  def secret_for(server_id)
    entry = secrets_hash[server_id.to_s]
    entry.is_a?(Hash) ? entry['config'] : nil
  end

  def secret_updated_at(server_id)
    entry = secrets_hash[server_id.to_s]
    entry.is_a?(Hash) && entry['updated_at'] ? Time.zone.parse(entry['updated_at']) : nil
  end

  def store_secret!(server_id, config_text)
    raise MultirdpLicenses::EncryptionUnavailable unless MultirdpLicenses::Encryption.ready?

    hash = secrets_hash
    entry = hash[server_id.to_s].is_a?(Hash) ? hash[server_id.to_s] : {}
    entry['config'] = config_text.to_s
    entry['updated_at'] = Time.now.utc.iso8601
    hash[server_id.to_s] = entry
    write_secrets!(hash)
  end

  def delete_secret!(server_id)
    hash = secrets_hash
    entry = hash[server_id.to_s]
    return false unless entry.is_a?(Hash) && entry.key?('config')

    entry.delete('config')
    entry.delete('updated_at')
    hash.delete(server_id.to_s) if entry.empty?
    write_secrets!(hash)
  end

  # ---- RDP-Kennwörter (Entscheidung des Auftraggebers vom 2026-09-23) ----

  def rdp_password_for(server_id)
    entry = secrets_hash[server_id.to_s]
    entry.is_a?(Hash) ? entry['rdp_password'] : nil
  end

  def rdp_password_updated_at(server_id)
    entry = secrets_hash[server_id.to_s]
    entry.is_a?(Hash) && entry['rdp_password_updated_at'] ? Time.zone.parse(entry['rdp_password_updated_at']) : nil
  end

  def store_rdp_password!(server_id, password)
    raise MultirdpLicenses::EncryptionUnavailable unless MultirdpLicenses::Encryption.ready?

    hash = secrets_hash
    entry = hash[server_id.to_s].is_a?(Hash) ? hash[server_id.to_s] : {}
    entry['rdp_password'] = password.to_s
    entry['rdp_password_updated_at'] = Time.now.utc.iso8601
    hash[server_id.to_s] = entry
    write_secrets!(hash)
  end

  def delete_rdp_password!(server_id)
    hash = secrets_hash
    entry = hash[server_id.to_s]
    return false unless entry.is_a?(Hash) && entry.key?('rdp_password')

    entry.delete('rdp_password')
    entry.delete('rdp_password_updated_at')
    hash.delete(server_id.to_s) if entry.empty?
    write_secrets!(hash)
  end

  def pending_devices
    devices.pending_open
  end

  def last_synced_at
    events.where(action: MultirdpEvent::SETTINGS_WRITTEN).maximum(:created_at)
  end

  private

  def write_secrets!(hash)
    self.secrets = hash.empty? ? nil : JSON.generate(hash)
    save!
  end

  def single_active_grant_per_user
    return unless status == STATUS_ACTIVE && !expired? && license

    others = MultirdpGrant.for_user(user_id).of_kind(license.kind).status_active.not_expired
    others = others.where.not(id: id) if persisted?
    errors.add(:user_id, :multirdp_user_already_licensed) if others.exists?
  end
end
