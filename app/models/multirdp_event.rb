# frozen_string_literal: true

# Protokoll: wer wann was. Nur anhängen, nie ändern.
class MultirdpEvent < ActiveRecord::Base
  LICENSE_CREATED  = 'license_created'
  LICENSE_UPDATED  = 'license_updated'
  LICENSE_DELETED  = 'license_deleted'
  GRANT_CREATED    = 'grant_created'
  GRANT_UPDATED    = 'grant_updated'
  GRANT_REVOKED    = 'grant_revoked'
  GRANT_DELETED    = 'grant_deleted'
  DEVICE_REQUESTED = 'device_requested'
  DEVICE_APPROVED  = 'device_approved'
  DEVICE_DENIED    = 'device_denied'
  DEVICE_EXPIRED   = 'device_expired'
  DEVICE_REVOKED   = 'device_revoked'
  SETTINGS_WRITTEN = 'settings_written'
  SECRET_STORED    = 'secret_stored'
  SECRET_DELETED   = 'secret_deleted'
  SECRET_FETCHED   = 'secret_fetched'
  LOGIN_ATTEMPT    = 'login_attempt'
  SESSION_ENDED    = 'session_ended'

  ACTIONS = [
    LICENSE_CREATED, LICENSE_UPDATED, LICENSE_DELETED,
    GRANT_CREATED, GRANT_UPDATED, GRANT_REVOKED, GRANT_DELETED,
    DEVICE_REQUESTED, DEVICE_APPROVED, DEVICE_DENIED, DEVICE_EXPIRED, DEVICE_REVOKED,
    SETTINGS_WRITTEN, SECRET_STORED, SECRET_DELETED, SECRET_FETCHED,
    LOGIN_ATTEMPT, SESSION_ENDED
  ].freeze

  belongs_to :grant, class_name: 'MultirdpGrant', optional: true
  belongs_to :device, class_name: 'MultirdpDevice', optional: true
  belongs_to :user, optional: true

  validates :action, inclusion: { in: ACTIONS }

  scope :sorted, -> { order(created_at: :desc, id: :desc) }

  # Einträge sind nach dem Anlegen unveränderlich.
  def readonly?
    persisted?
  end

  # Schreibt einen Eintrag. `detail` darf keine Geheimnisse enthalten.
  def self.record!(action, user: nil, grant: nil, device: nil, ip: nil, detail: nil)
    user ||= User.current if User.current&.logged?
    create!(
      action: action,
      user_id: user&.id,
      grant_id: grant&.id,
      device_id: device&.id,
      ip: ip.to_s.first(255).presence,
      detail: detail.to_s.first(4000).presence,
      created_at: Time.now
    )
  end

  def action_label
    ::I18n.t(:"label_multirdp_event_#{action}", default: action)
  end
end
