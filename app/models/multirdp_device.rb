# frozen_string_literal: true

require 'digest'

# Ein angemeldeter Client. Das Gerätetoken liegt nur als SHA-256-Hash vor.
class MultirdpDevice < ActiveRecord::Base
  STATUS_PENDING  = 'pending'
  STATUS_APPROVED = 'approved'
  STATUS_DENIED   = 'denied'
  STATUS_REVOKED  = 'revoked'
  STATUSES = [STATUS_PENDING, STATUS_APPROVED, STATUS_DENIED, STATUS_REVOKED].freeze

  belongs_to :grant, class_name: 'MultirdpGrant', inverse_of: :devices
  has_one :user, through: :grant
  has_many :events, class_name: 'MultirdpEvent', foreign_key: :device_id, dependent: :nullify

  validates :status, inclusion: { in: STATUSES }
  validates :token_digest, presence: true, uniqueness: true
  validates :name, length: { maximum: 255 }
  validates :platform, inclusion: { in: MultirdpLicenses::PLATFORMS }, allow_blank: true
  validates :app_version, length: { maximum: 64 }
  validates :public_key, length: { maximum: 255 }

  scope :sorted, -> { order(requested_at: :desc) }
  scope :pending_open, -> { where(status: STATUS_PENDING).where('requested_at > ?', MultirdpLicenses::PENDING_TTL.ago) }
  scope :approved, -> { where(status: STATUS_APPROVED) }

  # Erzeugt ein Token mit 32 Byte Entropie (64 Hex-Zeichen).
  def self.generate_token
    SecureRandom.hex(32)
  end

  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  # Sucht das Gerät zum Token; der Vergleich des Hashes läuft in konstanter Zeit.
  def self.authenticate(token)
    return nil if token.blank?

    digest = digest(token)
    device = find_by(token_digest: digest)
    return nil unless device && ActiveSupport::SecurityUtils.secure_compare(device.token_digest, digest)

    device
  end

  # Legt ein Gerät als "pending" an und gibt [device, token] zurück.
  def self.register!(grant:, name:, platform:, app_version:, ip:, public_key: nil)
    token = generate_token
    device = create!(
      grant: grant,
      token_digest: digest(token),
      name: name.to_s.strip.first(255),
      platform: platform.to_s.strip.downcase,
      app_version: app_version.to_s.strip.first(64),
      public_key: public_key.presence&.strip&.first(255),
      status: STATUS_PENDING,
      requested_at: Time.now,
      requested_ip: ip
    )
    [device, token]
  end

  def pending?
    status == STATUS_PENDING
  end

  def pending_expired?
    pending? && requested_at.present? && requested_at <= MultirdpLicenses::PENDING_TTL.ago
  end

  def pending_open?
    pending? && !pending_expired?
  end

  def approved?
    status == STATUS_APPROVED
  end

  def denied?
    status == STATUS_DENIED
  end

  def revoked?
    status == STATUS_REVOKED
  end

  # Abgelaufene Anfragen gelten als abgelehnt.
  def effective_status
    pending_expired? ? STATUS_DENIED : status
  end

  def status_label
    ::I18n.t(:"label_multirdp_device_status_#{effective_status}", default: effective_status)
  end

  def platform_label
    ::I18n.t(:"label_multirdp_platform_#{platform}", default: platform.to_s)
  end

  def approve!
    return false unless pending_open?

    update!(status: STATUS_APPROVED, approved_at: Time.now)
  end

  def deny!
    return false unless pending?

    update!(status: STATUS_DENIED)
  end

  def revoke!
    return false if revoked?

    update!(status: STATUS_REVOKED)
  end

  # Wird von der Schnittstelle bei jedem Aufruf gesetzt, ohne Callbacks.
  def touch_seen!(ip)
    update_columns(last_seen_at: Time.now, last_seen_ip: ip.to_s.first(255))
  end

  def to_s
    name.presence || "##{id}"
  end
end
