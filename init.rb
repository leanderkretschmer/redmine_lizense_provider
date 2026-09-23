# frozen_string_literal: true

require 'redmine'

# Der Verzeichnisname des Plugins muss "multirdp_licenses" lauten, sonst
# findet Redmine::Plugin.register das Plugin nicht (siehe README).
Redmine::Plugin.register :multirdp_licenses do
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
