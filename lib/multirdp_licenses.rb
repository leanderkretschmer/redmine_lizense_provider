# frozen_string_literal: true

# Ruby-Namensraum des Plugins "redmine_lizense_provider".
module MultirdpLicenses
  # Einzige Lizenzart bislang.
  KIND_MULTIRDP = 'multirdp'
  KINDS = [KIND_MULTIRDP].freeze

  # Wie lange eine Freigabeanfrage offen bleibt.
  PENDING_TTL = 15.minutes

  # Höchstzahl offener Freigabeanfragen je Benutzer.
  MAX_PENDING_PER_USER = 5

  # Anmeldeversuche je IP und Stunde auf POST /session.
  LOGIN_ATTEMPTS_PER_HOUR = 10

  # Voreinstellung der Nachfrist (Abschnitt 10 der Vorgabe).
  DEFAULT_GRACE_DAYS = 14

  # Größte erlaubte Einstellungen-Nutzlast (JSON) in Byte.
  MAX_SETTINGS_BYTES = 4 * 1024 * 1024

  # Erlaubte Plattformen des Clients.
  PLATFORMS = %w[macos windows].freeze
end
