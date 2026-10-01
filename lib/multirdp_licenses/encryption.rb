# frozen_string_literal: true

require 'digest'
require 'securerandom'

module MultirdpLicenses
  # Konfiguriert ActiveRecord::Encryption für die verschlüsselten Spalten
  # (multirdp_grants.secrets, multirdp_licenses.secrets).
  #
  # Schlüsselquellen in dieser Reihenfolge:
  #   1. ENV["MULTIRDP_KEY"]
  #   2. Datei config/multirdp_key (relativ zum Redmine-Wurzelverzeichnis)
  #   3. Plugin-Einstellung "encryption_key" in der Redmine-Datenbank; fehlt sie,
  #      erzeugt das Plugin beim ersten Start selbst einen Schlüssel und legt ihn dort ab.
  #      Achtung: Dann enthält ein Datenbankabzug auch den Schlüssel. ENV oder Datei
  #      sind die stärkere Wahl; der Schlüssel ist in der Plugin-Konfiguration einsehbar.
  #
  # Hat die Redmine-Instanz ActiveRecord::Encryption bereits selbst konfiguriert,
  # wird deren Konfiguration unverändert benutzt.
  module Encryption
    ENV_NAME  = 'MULTIRDP_KEY'
    FILE_NAME = 'multirdp_key'
    SETTING_NAME = 'encryption_key'
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
          Rails.logger.error("[redmine_lizense_provider] Kein Verschlüsselungsschlüssel (#{@problem}): weder ENV #{ENV_NAME}, " \
                             "noch #{key_file_path}, noch Plugin-Einstellung. Geheimnisse können nicht gespeichert werden.") if Rails.logger
          return false
        end

        cfg = ActiveRecord::Encryption.config
        cfg.primary_key         = key
        cfg.deterministic_key   = Digest::SHA256.hexdigest("multirdp-deterministic:#{key}")
        cfg.key_derivation_salt = Digest::SHA256.hexdigest("multirdp-salt:#{key}")
        ActiveRecord::Encryption.reset_default_context if ActiveRecord::Encryption.respond_to?(:reset_default_context)
        @configured_by_plugin = true
        @current_key = key
        true
      end

      # true, wenn ein Schlüssel vorliegt. Versucht die Konfiguration nachzuholen,
      # falls sie beim Start (z. B. ohne Datenbank) noch nicht möglich war.
      def ready?
        host_configured? || configure!
      end

      def configured_by_plugin?
        @configured_by_plugin == true
      end

      # Woher der Schlüssel stammt: :env, :file, :database, :test, :host (Redmine selbst) oder nil.
      def source
        return @source if configured_by_plugin?

        host_configured? ? :host : nil
      end

      # Der aktive Schlüssel, nur wenn das Plugin ihn selbst gesetzt hat.
      def current_key
        configured_by_plugin? ? @current_key : nil
      end

      # Warum kein Schlüssel vorliegt: :missing oder :too_short (nil, wenn alles gut ist).
      def problem
        return nil if ready?

        @problem || :missing
      end

      def key_file_path
        Rails.root.join('config', FILE_NAME)
      end

      # Nur für Tests: Konfiguration zurücksetzen.
      def reset_for_tests!
        @configured_by_plugin = nil
        @problem = nil
        @source = nil
        @current_key = nil
        cfg = ActiveRecord::Encryption.config
        cfg.primary_key = nil
        cfg.deterministic_key = nil
        cfg.key_derivation_salt = nil
      end

      # Liefert den in der Datenbank abgelegten Schlüssel; erzeugt ihn bei Bedarf.
      # nil, wenn die Datenbank oder die Einstellungen nicht erreichbar sind.
      def stored_or_generated_key
        return nil unless ActiveRecord::Base.connection.data_source_exists?('settings')

        settings = Setting.plugin_redmine_lizense_provider
        settings = settings.is_a?(Hash) ? settings.stringify_keys : {}
        key = settings[SETTING_NAME].to_s.strip
        if key.empty?
          key = SecureRandom.hex(32)
          Setting.plugin_redmine_lizense_provider = settings.merge(SETTING_NAME => key)
          Rails.logger.info('[redmine_lizense_provider] Verschlüsselungsschlüssel erzeugt und in den Plugin-Einstellungen abgelegt.') if Rails.logger
        end
        key
      rescue StandardError => e
        Rails.logger.warn("[redmine_lizense_provider] Schlüssel aus den Einstellungen nicht verfügbar: #{e.class}: #{e.message}") if Rails.logger
        nil
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
        source = :env
        if key.empty? && File.readable?(key_file_path)
          key = File.read(key_file_path).strip
          source = :file
        end
        if key.empty? && Rails.env.test?
          key = TEST_KEY
          source = :test
        end
        if key.empty?
          key = stored_or_generated_key.to_s
          source = :database
        end
        if key.empty?
          @problem = :missing
          return nil
        end

        if key.length < MIN_KEY_LENGTH
          @problem = :too_short
          Rails.logger.error("[redmine_lizense_provider] Verschlüsselungsschlüssel aus #{source} zu kurz (#{key.length} Zeichen, mindestens #{MIN_KEY_LENGTH}).") if Rails.logger
          return nil
        end
        @problem = nil
        @source = source
        key
      end
    end
  end
end
