# frozen_string_literal: true

require 'digest'

module MultirdpLicenses
  # Konfiguriert ActiveRecord::Encryption für die Spalte multirdp_grants.secrets.
  #
  # Redmine 6 bringt keine Rails-Credentials mit; deshalb holt das Plugin den
  # Schlüssel aus ENV["MULTIRDP_KEY"] oder aus der Datei config/multirdp_key
  # (relativ zum Redmine-Wurzelverzeichnis). Hat die Redmine-Instanz
  # ActiveRecord::Encryption bereits selbst konfiguriert, wird deren
  # Konfiguration unverändert benutzt.
  module Encryption
    ENV_NAME  = 'MULTIRDP_KEY'
    FILE_NAME = 'multirdp_key'
    MIN_KEY_LENGTH = 32

    # Fester Schlüssel für die Testumgebung, damit die Tests ohne Datei laufen.
    TEST_KEY = 'multirdp-licenses-test-key-0000000000000000000000000000'

    class << self
      # Führt die Konfiguration aus, falls noch keine vorliegt. Gibt true
      # zurück, wenn danach verschlüsselt werden kann.
      def configure!
        return true if host_configured?

        key = load_key
        if key.nil?
          Rails.logger.error("[multirdp_licenses] Kein Verschlüsselungsschlüssel: weder ENV #{ENV_NAME} " \
                             "noch #{key_file_path} vorhanden. WireGuard-Konfigurationen können nicht " \
                             "gespeichert werden.") if Rails.logger
          return false
        end

        cfg = ActiveRecord::Encryption.config
        cfg.primary_key         = key
        cfg.deterministic_key   = Digest::SHA256.hexdigest("multirdp-deterministic:#{key}")
        cfg.key_derivation_salt = Digest::SHA256.hexdigest("multirdp-salt:#{key}")
        ActiveRecord::Encryption.reset_default_context if ActiveRecord::Encryption.respond_to?(:reset_default_context)
        @configured_by_plugin = true
        true
      end

      # true, wenn ein Schlüssel vorliegt (egal ob vom Plugin oder von Redmine).
      def ready?
        host_configured?
      end

      def configured_by_plugin?
        @configured_by_plugin == true
      end

      def key_file_path
        Rails.root.join('config', FILE_NAME)
      end

      # Nur für Tests: Konfiguration zurücksetzen.
      def reset_for_tests!
        @configured_by_plugin = nil
        cfg = ActiveRecord::Encryption.config
        cfg.primary_key = nil
        cfg.deterministic_key = nil
        cfg.key_derivation_salt = nil
      end

      private

      def host_configured?
        # primary_key wirft Errors::Configuration, wenn nichts gesetzt ist.
        ActiveRecord::Encryption.config.primary_key.present?
      rescue ActiveRecord::Encryption::Errors::Configuration
        false
      end

      def load_key
        key = ENV[ENV_NAME].to_s.strip
        key = File.read(key_file_path).strip if key.empty? && File.readable?(key_file_path)
        key = TEST_KEY if key.empty? && Rails.env.test?
        return nil if key.empty?

        if key.length < MIN_KEY_LENGTH
          Rails.logger.error("[multirdp_licenses] Verschlüsselungsschlüssel zu kurz (mindestens #{MIN_KEY_LENGTH} Zeichen).") if Rails.logger
          return nil
        end
        key
      end
    end
  end
end
