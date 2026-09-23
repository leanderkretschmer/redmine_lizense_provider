# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# Spielt die Abnahme (Abschnitt 14) über die Schnittstelle durch.
class MultirdpApiTest < Redmine::IntegrationTest
  include MultirdpTestHelper
  fixtures :users, :email_addresses, :user_preferences, :roles

  def setup
    https!
    @license = create_license
    @user = User.find(2) # jsmith / jsmith
    @grant = create_grant(@license, @user)
  end

  def json
    JSON.parse(response.body)
  end

  def auth(token)
    { 'Authorization' => "Bearer #{token}" }
  end

  def login(password = 'jsmith', device: { name: 'MacBook von Leander', platform: 'macos', app_version: '1.4.2' })
    post '/multirdp/api/v1/session', params: { login: 'jsmith', password: password, device: device }.to_json,
                                     headers: { 'CONTENT_TYPE' => 'application/json' }
  end

  def login_and_approve
    login
    assert_response :success
    token = json['token']
    MultirdpDevice.authenticate(token).approve!
    token
  end

  # Abschnitt 7: Freigeben und Ablehnen nur per POST.
  def test_get_does_not_approve
    login
    device = MultirdpDevice.authenticate(json['token'])
    log_user('jsmith', 'jsmith')
    begin
      get "/my/licenses/devices/#{device.id}/approve"
      assert_response 404
    rescue ActionController::RoutingError
      # Kein GET-Routing vorhanden: ebenfalls in Ordnung.
    end
    assert_equal 'pending', device.reload.status
  end

  # Abschnitt 12.1: nur HTTPS, abweisen statt umleiten.
  def test_http_is_rejected
    https!(false)
    login
    assert_response 403
    assert_equal 'https_erforderlich', json['error']
  end

  # Abnahme 2
  def test_session_returns_pending_token_and_license_is_202
    login
    assert_response :success
    assert_equal 'pending', json['status']
    assert_match(%r{/my/licenses\z}, json['approve_url'])
    token = json['token']
    assert_equal 64, token.length

    device = MultirdpDevice.authenticate(token)
    assert_equal 'pending', device.status
    assert_equal 'MacBook von Leander', device.name
    assert_equal 1, MultirdpEvent.where(action: 'device_requested', device_id: device.id).count

    get '/multirdp/api/v1/license', headers: auth(token)
    assert_response 202
    assert_equal 'pending', json['status']
    assert device.reload.last_seen_at.present?
  end

  def test_password_never_stored
    login
    assert_response :success
    assert_equal 0, MultirdpEvent.where('detail LIKE ?', '%jsmith%password%').count
    MultirdpEvent.find_each { |e| assert_no_match(/jsmith\W*jsmith/, e.detail.to_s) }
  end

  def test_wrong_password_and_no_license
    login('falsch')
    assert_response 401
    assert_equal 'anmeldung_fehlgeschlagen', json['error']

    @grant.destroy
    login
    assert_response 403
    assert_equal 'keine_lizenz', json['error']
  end

  def test_invalid_platform_rejected
    login(device: { name: 'x', platform: 'linux', app_version: '1' })
    assert_response 422
  end

  # Abnahme 3 + 4
  def test_approval_then_license_and_secret
    login
    token = json['token']
    device = MultirdpDevice.authenticate(token)

    # Benutzer öffnet eine Redmine-Seite, sieht das Fenster und gibt frei.
    log_user('jsmith', 'jsmith')
    get '/my/page'
    assert_response :success
    assert_select '#multirdp-approval', 1
    assert_select '#multirdp-approval form[action=?]', "/my/licenses/devices/#{device.id}/approve"
    post "/my/licenses/devices/#{device.id}/approve"
    assert_redirected_to '/my/licenses'
    assert_equal 'approved', device.reload.status
    get '/my/page'
    assert_select '#multirdp-approval', 0
    reset!
    https!

    @grant.store_secret!(SERVER_ID, "[Interface]\nPrivateKey = KEY==\n[Peer]\nEndpoint = vpn.example.de:51820\n")

    get '/multirdp/api/v1/license', headers: auth(token)
    assert_response :success
    assert_equal 'active', json['status']
    assert_equal @license.id, json['license']['id']
    assert_nil json['license']['valid_until']
    assert_equal 1, json['revision']
    assert_equal 0, json['settings_revision']
    assert_equal 14, json['grace_days']
    assert_equal 1, json['data']['servers'].size
    assert_equal 2, json['data']['apps'].size
    assert_equal [SERVER_ID], json['secrets_available']
    etag = response.etag
    assert etag.present?

    get '/multirdp/api/v1/license', headers: auth(token).merge('If-None-Match' => etag)
    assert_response 304

    get "/multirdp/api/v1/secrets/#{SERVER_ID}", headers: auth(token)
    assert_response :success
    assert_match(/PrivateKey = KEY==/, response.body)
    assert_equal 'no-store', response.headers['Cache-Control']
    event = MultirdpEvent.where(action: 'secret_fetched', device_id: device.id).last
    assert event
    assert_equal '127.0.0.1', event.ip
    assert_no_match(/KEY==/, event.detail)

    get '/multirdp/api/v1/secrets/ffffffff-0000-0000-0000-000000000000', headers: auth(token)
    assert_response 404
  end

  def test_rdp_password_endpoint
    token = login_and_approve
    device = MultirdpDevice.authenticate(token)
    get "/multirdp/api/v1/secrets/#{SERVER_ID}/rdp", headers: auth(token)
    assert_response 404
    assert_equal 'kein_geheimnis', json['error']

    @grant.store_rdp_password!(SERVER_ID, 'RdpGeheim!')
    get '/multirdp/api/v1/license', headers: auth(token)
    assert_equal [SERVER_ID], json['rdp_passwords_available']
    assert_equal [], json['secrets_available']
    assert_no_match(/RdpGeheim/, response.body)

    get "/multirdp/api/v1/secrets/#{SERVER_ID}/rdp", headers: auth(token)
    assert_response :success
    assert_equal 'RdpGeheim!', json['password']
    assert_equal 'no-store', response.headers['Cache-Control']
    event = MultirdpEvent.where(action: 'rdp_password_fetched', device_id: device.id).last
    assert event
    assert_no_match(/RdpGeheim/, event.detail)

    device.revoke!
    get "/multirdp/api/v1/secrets/#{SERVER_ID}/rdp", headers: auth(token)
    assert_response 403
    assert_equal 'geraet_gesperrt', json['error']
  end

  # Abnahme 5
  def test_settings_write_and_conflict
    token = login_and_approve
    put '/multirdp/api/v1/settings', params: { settings_revision: 0, settings: sample_settings }.to_json,
                                     headers: auth(token).merge('CONTENT_TYPE' => 'application/json')
    assert_response :success
    assert_equal 1, json['settings_revision']
    assert_equal 20, @grant.reload.settings['transfer']['reconnectAttempts']

    put '/multirdp/api/v1/settings', params: { settings_revision: 0, settings: sample_settings }.to_json,
                                     headers: auth(token).merge('CONTENT_TYPE' => 'application/json')
    assert_response 409
    assert_equal 'revision_konflikt', json['error']
    assert_equal 1, json['settings_revision']
    assert_equal 20, json['settings']['transfer']['reconnectAttempts']

    # Änderung an data wird abgewiesen
    put '/multirdp/api/v1/settings', params: { settings_revision: 1, settings: sample_settings, data: {} }.to_json,
                                     headers: auth(token).merge('CONTENT_TYPE' => 'application/json')
    assert_response 403
    assert_equal 'data_schreibgeschuetzt', json['error']
    put '/multirdp/api/v1/data', params: { servers: [] }.to_json, headers: auth(token).merge('CONTENT_TYPE' => 'application/json')
    assert_response 403
    assert_equal 1, @license.reload.revision

    # Ungültige Einstellungen
    put '/multirdp/api/v1/settings', params: { settings_revision: 1, settings: { 'transfer' => { 'clipboard' => 'ja' }, 'foo' => 1 } }.to_json,
                                     headers: auth(token).merge('CONTENT_TYPE' => 'application/json')
    assert_response 422
    assert_equal 'ungueltige_einstellungen', json['error']
    assert_equal 1, @grant.reload.settings_revision

    # ETag ändert sich mit settings_revision
    get '/multirdp/api/v1/license', headers: auth(token)
    assert_equal 1, json['settings_revision']
  end

  # Abnahme 6
  def test_admin_change_bumps_revision
    token = login_and_approve
    get '/multirdp/api/v1/license', headers: auth(token)
    etag = response.etag
    data = @license.data
    data['servers'][0]['host'] = '10.9.9.9'
    @license.data = data
    @license.save!
    get '/multirdp/api/v1/license', headers: auth(token).merge('If-None-Match' => etag)
    assert_response :success
    assert_equal 2, json['revision']
    assert_equal '10.9.9.9', json['data']['servers'][0]['host']
  end

  # Abnahme 7
  def test_user_revokes_device
    token = login_and_approve
    device = MultirdpDevice.authenticate(token)
    device.revoke!
    get '/multirdp/api/v1/license', headers: auth(token)
    assert_response 403
    assert_equal 'geraet_gesperrt', json['error']
    get "/multirdp/api/v1/secrets/#{SERVER_ID}", headers: auth(token)
    assert_response 403
  end

  def test_denied_and_expired_pending
    login
    token = json['token']
    device = MultirdpDevice.authenticate(token)
    device.update_columns(requested_at: 16.minutes.ago)
    get '/multirdp/api/v1/license', headers: auth(token)
    assert_response 403
    assert_equal 'geraet_gesperrt', json['error']
    assert_equal 'denied', device.reload.status
    assert_equal 1, MultirdpEvent.where(action: 'device_expired', device_id: device.id).count
  end

  # Abnahme 8
  def test_grant_revoked_suspended_expired
    token = login_and_approve
    @grant.update!(status: 'revoked')
    get '/multirdp/api/v1/license', headers: auth(token)
    assert_response 403
    assert_equal 'entzogen', json['error']

    @grant.update!(status: 'suspended')
    get '/multirdp/api/v1/license', headers: auth(token)
    assert_equal 'entzogen', json['error']

    @grant.update!(status: 'active', valid_until: Date.yesterday)
    get '/multirdp/api/v1/license', headers: auth(token)
    assert_response 403
    assert_equal 'abgelaufen', json['error']
  end

  # Abnahme 9
  def test_rate_limit_per_ip
    10.times do
      login('falsch')
      assert_response 401
    end
    login('falsch')
    assert_response 429
    assert_equal 'zu_viele_versuche', json['error']
    login
    assert_response 429
  end

  def test_max_pending_per_user
    5.times do
      login
      assert_response :success
    end
    login
    assert_response 429
    assert_equal 'zu_viele_anfragen', json['error']
  end

  def test_token_is_not_a_redmine_api_key
    token = login_and_approve
    get '/users/current.json', headers: auth(token)
    assert_includes [401, 403], response.status
    get '/my/account', headers: auth(token)
    assert_response 302
  end

  def test_bad_token
    get '/multirdp/api/v1/license', headers: auth('nope')
    assert_response 401
    assert_equal 'token_ungueltig', json['error']
    get '/multirdp/api/v1/license'
    assert_response 401
  end

  def test_logout
    token = login_and_approve
    delete '/multirdp/api/v1/session', headers: auth(token)
    assert_response :success
    assert_equal 'revoked', json['status']
    get '/multirdp/api/v1/license', headers: auth(token)
    assert_response 403
    assert_equal 'geraet_gesperrt', json['error']
  end

  def test_public_key_is_stored_for_way_b
    login(device: { name: 'x', platform: 'windows', app_version: '0.1', public_key: 'AbCdEf=' })
    assert_response :success
    assert_equal 'AbCdEf=', MultirdpDevice.authenticate(json['token']).public_key
  end

  # Abnahme 10
  def test_database_contains_no_plaintext_secret
    @grant.store_secret!(SERVER_ID, "[Interface]\nPrivateKey = PLAINTEXTKEY==\n")
    @grant.store_rdp_password!(SERVER_ID, 'PLAINTEXTRDP')
    raw = ActiveRecord::Base.connection.select_value("SELECT secrets FROM multirdp_grants WHERE id = #{@grant.id}")
    assert_not_includes raw.to_s, 'PLAINTEXTKEY'
    assert_not_includes raw.to_s, 'PLAINTEXTRDP'
    assert_equal 0, MultirdpEvent.where('detail LIKE ?', '%PLAINTEXTKEY%').count
  end
end
