# frozen_string_literal: true

# Eine Lizenz: Vorgabe des Administrators (`data`) plus Nachfrist.
class MultirdpLicense < ActiveRecord::Base
  include Redmine::SafeAttributes

  has_many :grants, class_name: 'MultirdpGrant', foreign_key: :license_id, dependent: :destroy, inverse_of: :license
  has_many :users, through: :grants
  belongs_to :created_by, class_name: 'User', optional: true

  serialize :data, coder: JSON
  # RDP-Kennwörter je Server, verschlüsselt: JSON server_id => {rdp_password, updated_at}.
  encrypts :secrets

  validates :name, presence: true, length: { maximum: 255 }
  validates :kind, inclusion: { in: MultirdpLicenses::KINDS }
  validates :grace_days, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 3650 }
  validate :validate_data_schema

  before_validation :ensure_defaults
  before_update :bump_revision, if: :will_save_change_to_data?
  before_save :prune_rdp_passwords

  safe_attributes 'name', 'notes', 'grace_days'

  scope :sorted, -> { order(:name) }

  def data
    value = super
    value.is_a?(Hash) ? value : MultirdpLicenses::DataSchema.empty_data
  end

  # Weist eine normalisierte Vorgabe zu (Hash mit "servers" und "apps").
  def data=(value)
    super(MultirdpLicenses::DataSchema.normalize_data(value))
  end

  def servers
    Array(data['servers'])
  end

  def apps
    Array(data['apps'])
  end

  def server(id)
    servers.find { |s| s['id'] == id.to_s.downcase }
  end

  def apps_for(server_id)
    apps.select { |a| a['serverId'] == server_id }
  end

  def server_ids
    servers.map { |s| s['id'] }
  end

  # ---- RDP-Kennwörter je Server (Entscheidung des Auftraggebers) -------------

  def secrets_hash
    return {} unless MultirdpLicenses::Encryption.ready?

    parsed = secrets.present? ? JSON.parse(secrets) : {}
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError, ActiveRecord::Encryption::Errors::Base
    {}
  end

  def rdp_password_for(server_id)
    entry = secrets_hash[server_id.to_s]
    entry.is_a?(Hash) ? entry['rdp_password'] : nil
  end

  def rdp_password_updated_at(server_id)
    entry = secrets_hash[server_id.to_s]
    entry.is_a?(Hash) && entry['updated_at'] ? Time.zone.parse(entry['updated_at']) : nil
  end

  def rdp_password_server_ids
    secrets_hash.select { |_, e| e.is_a?(Hash) && e['rdp_password'].present? }.keys
  end

  # Setzt ein Kennwort im Speicher; gespeichert wird mit save.
  def set_rdp_password(server_id, password)
    raise MultirdpLicenses::EncryptionUnavailable unless MultirdpLicenses::Encryption.ready?

    hash = secrets_hash
    hash[server_id.to_s] = { 'rdp_password' => password.to_s, 'updated_at' => Time.now.utc.iso8601 }
    self.secrets = JSON.generate(hash)
  end

  def remove_rdp_password(server_id)
    hash = secrets_hash
    return false unless hash.delete(server_id.to_s)

    self.secrets = hash.empty? ? nil : JSON.generate(hash)
    true
  end

  def kind_label
    ::I18n.t(:"label_multirdp_kind_#{kind}", default: kind)
  end

  def to_s
    name
  end

  private

  def ensure_defaults
    self.kind = MultirdpLicenses::KIND_MULTIRDP if kind.blank?
    self.grace_days = MultirdpLicenses::DEFAULT_GRACE_DAYS if grace_days.nil?
    self.revision = 1 if revision.nil? || revision < 1
    self[:data] = MultirdpLicenses::DataSchema.empty_data if self[:data].nil?
  end

  # Kennwörter gelöschter Server mit entfernen.
  def prune_rdp_passwords
    return if secrets.blank? || !MultirdpLicenses::Encryption.ready?

    hash = secrets_hash
    kept = hash.slice(*server_ids)
    self.secrets = kept.empty? ? nil : JSON.generate(kept) if kept.size != hash.size
  end

  def bump_revision
    self.revision = (revision || 1) + 1
  end

  def validate_data_schema
    MultirdpLicenses::DataSchema.validate_data(data).each do |err|
      errors.add(:data, err.message)
    end
  end
end
