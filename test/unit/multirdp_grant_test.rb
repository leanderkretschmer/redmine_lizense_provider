# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class MultirdpGrantTest < ActiveSupport::TestCase
  include MultirdpTestHelper
  fixtures :users, :email_addresses

  def setup
    @license = create_license
    @user = User.find(2)
  end

  def test_effective_status
    grant = create_grant(@license, @user)
    assert_equal 'active', grant.effective_status
    assert_nil grant.denial_reason

    grant.update!(valid_until: Date.yesterday)
    assert_equal 'expired', grant.effective_status
    assert_equal 'abgelaufen', grant.denial_reason

    grant.update!(valid_until: nil, status: 'suspended')
    assert_equal 'entzogen', grant.denial_reason
    grant.update!(status: 'revoked')
    assert_equal 'entzogen', grant.denial_reason
  end

  def test_user_can_hold_license_only_once
    create_grant(@license, @user)
    dup = @license.grants.build(user: @user)
    assert_not dup.valid?
  end

  def test_only_one_active_multirdp_grant_per_user
    other = create_license(name: 'Andere')
    create_grant(@license, @user)
    second = other.grants.build(user: @user, status: 'active')
    assert_not second.valid?
    assert second.errors[:user_id].any?

    second.status = 'suspended'
    assert second.valid?
  end

  def test_effective_for_ignores_expired_and_revoked
    grant = create_grant(@license, @user, valid_until: Date.yesterday)
    assert_nil MultirdpGrant.effective_for(@user)
    grant.update!(valid_until: nil)
    assert_equal grant, MultirdpGrant.effective_for(@user)
    grant.update!(status: 'revoked')
    assert_nil MultirdpGrant.effective_for(@user)
  end

  def test_write_settings_with_revision_check
    grant = create_grant(@license, @user)
    assert_equal 0, grant.settings_revision
    assert grant.write_settings!(sample_settings, 0)
    assert_equal 1, grant.reload.settings_revision
    assert_equal true, grant.settings['transfer']['autoReconnect']
    assert_not grant.write_settings!(sample_settings, 0)
    assert_equal 1, grant.reload.settings_revision
  end

  def test_secrets_are_encrypted_at_rest
    assert MultirdpLicenses::Encryption.ready?, 'Verschlüsselung nicht konfiguriert'
    grant = create_grant(@license, @user)
    config = "[Interface]\nPrivateKey = SUPERSECRETPRIVATEKEY==\n"
    grant.store_secret!(SERVER_ID, config)

    raw = MultirdpGrant.connection.select_value("SELECT secrets FROM multirdp_grants WHERE id = #{grant.id}")
    assert raw.present?
    assert_not_includes raw, 'SUPERSECRETPRIVATEKEY'
    assert_not_includes raw, 'PrivateKey'

    assert_equal config, grant.reload.secret_for(SERVER_ID)
    assert_equal [SERVER_ID], grant.secret_server_ids
    assert grant.secret_updated_at(SERVER_ID).present?

    assert grant.delete_secret!(SERVER_ID)
    assert_nil grant.reload.secret_for(SERVER_ID)
  end

  def test_rdp_password_stored_encrypted_and_independent_of_wireguard
    grant = create_grant(@license, @user)
    grant.store_rdp_password!(SERVER_ID, 'Geheim#2026')
    raw = MultirdpGrant.connection.select_value("SELECT secrets FROM multirdp_grants WHERE id = #{grant.id}")
    assert_not_includes raw, 'Geheim#2026'
    assert_equal 'Geheim#2026', grant.reload.rdp_password_for(SERVER_ID)
    assert_equal [SERVER_ID], grant.rdp_password_server_ids
    assert_equal [], grant.secret_server_ids, 'Kennwort darf nicht als VPN-Konfiguration zählen'

    grant.store_secret!(SERVER_ID, "[Interface]\nPrivateKey = X==\n")
    assert_equal [SERVER_ID], grant.reload.secret_server_ids
    assert_equal 'Geheim#2026', grant.rdp_password_for(SERVER_ID)

    assert grant.delete_secret!(SERVER_ID)
    assert_equal 'Geheim#2026', grant.reload.rdp_password_for(SERVER_ID)
    assert grant.delete_rdp_password!(SERVER_ID)
    assert_nil grant.reload.rdp_password_for(SERVER_ID)
    assert_nil grant.secrets
    assert_not grant.delete_rdp_password!(SERVER_ID)
  end

  def test_events_are_append_only
    grant = create_grant(@license, @user)
    event = MultirdpEvent.record!(MultirdpEvent::GRANT_CREATED, grant: grant, user: @user, ip: '1.2.3.4')
    assert event.persisted?
    assert_raises(ActiveRecord::ReadOnlyRecord) { event.update!(detail: 'x') }
    assert_raises(ActiveRecord::ReadOnlyRecord) { event.destroy }
  end
end
