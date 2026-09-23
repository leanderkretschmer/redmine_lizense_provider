# frozen_string_literal: true

module MultirdpLicenses
  # Wird geworfen, wenn Geheimnisse gespeichert werden sollen, aber kein
  # Verschlüsselungsschlüssel konfiguriert ist.
  class EncryptionUnavailable < StandardError
    def initialize(msg = nil)
      super(msg || "Kein Verschlüsselungsschlüssel (ENV #{Encryption::ENV_NAME} oder #{Encryption::FILE_NAME}).")
    end
  end
end
