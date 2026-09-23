# frozen_string_literal: true

require 'redmine'

# Der Verzeichnisname des Plugins muss "redmine_lizense_provider" lauten
# (Plugin-Kennung = Repo-Name), sonst findet Redmine::Plugin.register das
# Plugin nicht.
#
# Einmalige Korrektur: Die ersten Fassungen liefen unter der Kennung
# "multirdp_licenses". Redmine merkt sich Plugin-Migrationen in
# schema_migrations als "<nr>-<kennung>"; ohne Umbenennung würden die vier
# Migrationen gegen bestehende Tabellen erneut laufen.
begin
  conn = ActiveRecord::Base.connection
  if conn.data_source_exists?('schema_migrations')
    old_suffix = '-multirdp_licenses'
    new_suffix = '-redmine_lizense_provider'
    rows = conn.select_values("SELECT version FROM schema_migrations WHERE version LIKE #{conn.quote("%#{old_suffix}")}")
    rows.each do |old_version|
      new_version = old_version.sub(/#{Regexp.escape(old_suffix)}\z/, new_suffix)
      next if old_version == new_version

      if conn.select_value("SELECT 1 FROM schema_migrations WHERE version = #{conn.quote(new_version)}")
        conn.execute("DELETE FROM schema_migrations WHERE version = #{conn.quote(old_version)}")
      else
        conn.execute("UPDATE schema_migrations SET version = #{conn.quote(new_version)} WHERE version = #{conn.quote(old_version)}")
      end
    end
  end
rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
  # Datenbank noch nicht bereit (Ersteinrichtung): nichts zu tun.
rescue StandardError => e
  Rails.logger.warn("[redmine_lizense_provider] schema_migrations-Umbenennung übersprungen: #{e.class}: #{e.message}") if defined?(Rails) && Rails.logger
end

Redmine::Plugin.register :redmine_lizense_provider do
  name 'multiRDP Lizenzen'
  author 'Leander Kretschmer'
  description 'Lizenzen für den multiRDP-Client: Zuteilung an Benutzer, Gerätefreigabe, ' \
              'Verteilung der Einrichtung und der WireGuard-Konfiguration über eine eigene Schnittstelle. / ' \
              'Licenses for the multiRDP client: per-user grants, device approval, ' \
              'distribution of configuration and WireGuard secrets via a dedicated API.'
  version '0.1.0'
  url 'https://github.com/leanderkretschmer/redmine_lizense_provider'
  author_url 'https://github.com/leanderkretschmer'

  requires_redmine version_or_higher: '6.0.0'

  menu :admin_menu, :multirdp_licenses,
       { controller: 'multirdp_licenses', action: 'index' },
       caption: :label_multirdp_licenses,
       icon: 'key',
       html: { class: 'icon icon-passwd' }
end

# Token und Geheimnisse dürfen in keinem Protokoll auftauchen.
Rails.application.config.filter_parameters += [:token, :password, :secrets, :config, :wireguard_config]

# Verschlüsselung der WireGuard-Konfigurationen (ActiveRecord::Encryption).
# Idempotent; der Schlüssel kommt aus ENV MULTIRDP_KEY oder config/multirdp_key.
MultirdpLicenses::Encryption.configure!

# Hook-Listener registrieren. Das ist kein Patch an Redmine-Klassen, deshalb
# direkt beim Laden; in to_prepare zusätzlich, damit er nach einem Neuladen
# im Entwicklungsmodus wieder vorhanden ist.
MultirdpLicenses::Hooks
Rails.application.config.to_prepare do
  MultirdpLicenses::Hooks
end
