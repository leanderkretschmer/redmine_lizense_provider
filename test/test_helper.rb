# frozen_string_literal: true

# Lädt Redmines Test-Helfer; die Plugin-Tests laufen mit
#   bundle exec rake redmine:plugins:test NAME=redmine_lizense_provider RAILS_ENV=test
require File.expand_path(File.dirname(__FILE__) + '/../../../test/test_helper')
require 'zlib'

# Die Redmine-Instanz kann in configuration.yml einen echten SMTP-Versand
# für alle Umgebungen vorgeben; die Plugin-Tests dürfen nie Mails verschicken.
ActionMailer::Base.delivery_method = :test
ActionMailer::Base.perform_deliveries = true

module MultirdpTestHelper
  SERVER_ID = '11111111-2222-3333-4444-555555555555'
  APP_ID    = '66666666-7777-8888-9999-000000000000'
  APP2_ID   = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'

  # Erzeugt ein gültiges PNG (RGBA, leer) der angegebenen Größe.
  def build_png(width, height)
    row = ([0] * (width * 4 + 1)).pack('C*')
    raw = row * height
    chunk = lambda do |type, data|
      [data.bytesize].pack('N') + type + data + [Zlib.crc32(type + data)].pack('N')
    end
    "\x89PNG\r\n\x1a\n".b +
      chunk.call('IHDR', [width, height, 8, 6, 0, 0, 0].pack('NNCCCCC')) +
      chunk.call('IDAT', Zlib::Deflate.deflate(raw)) +
      chunk.call('IEND', '')
  end

  def png_base64(width = 64, height = 64)
    MultirdpLicenses::IconValidator.encode(build_png(width, height))
  end

  def sample_data(icon: nil)
    {
      'servers' => [
        { 'id' => SERVER_ID, 'name' => 'winserver-dev', 'host' => '192.168.6.46', 'port' => 3389,
          'username' => 'franziska.nickel', 'domain' => '', 'vpnMode' => 1, 'vpnEndpoint' => 'vpn.example.de:51820' }
      ],
      'apps' => [
        { 'id' => APP_ID, 'serverId' => SERVER_ID, 'name' => 'Revit 2026',
          'program' => 'C:\\Program Files\\Autodesk\\Revit 2026\\Revit.exe', 'arguments' => '',
          'processName' => 'revit.exe', 'knownApplicationIds' => [], 'icon' => icon },
        { 'id' => APP2_ID, 'serverId' => SERVER_ID, 'name' => 'Excel',
          'program' => 'C:\\Program Files\\Microsoft Office\\EXCEL.EXE', 'arguments' => '',
          'processName' => 'excel.exe', 'knownApplicationIds' => [], 'icon' => icon }
      ]
    }
  end

  def create_license(attrs = {})
    MultirdpLicense.create!({ name: 'multiRDP — Büro Hamburg', kind: 'multirdp', data: sample_data,
                              created_by: User.find(1) }.merge(attrs))
  end

  def create_grant(license, user, attrs = {})
    license.grants.create!({ user: user, status: 'active' }.merge(attrs))
  end

  def create_device(grant, attrs = {})
    device, token = MultirdpDevice.register!(
      grant: grant, name: attrs[:name] || 'MacBook von Leander', platform: attrs[:platform] || 'macos',
      app_version: attrs[:app_version] || '1.4.2', ip: attrs[:ip] || '192.168.118.210'
    )
    device.update!(status: attrs[:status]) if attrs[:status]
    [device, token]
  end

  def sample_settings
    {
      'transfer' => { 'maxApps' => 0, 'autoReconnect' => true, 'reconnectAttempts' => 20, 'sound' => 0,
                      'microphone' => false, 'clipboard' => true, 'multimon' => true, 'shareMode' => 0,
                      'scalePercent' => 0 },
      'workspace' => { 'saveOnQuit' => true, 'restoreFromLink' => true, 'savedAt' => '2026-09-23T08:15:00Z',
                       'items' => [{ 'appId' => APP_ID, 'serverRect' => [0, 0, 1280, 800],
                                     'minimized' => false, 'maximized' => false }] },
      'ownApps' => []
    }
  end
end
