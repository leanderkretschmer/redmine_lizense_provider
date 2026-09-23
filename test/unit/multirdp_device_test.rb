# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class MultirdpDeviceTest < ActiveSupport::TestCase
  include MultirdpTestHelper
  fixtures :users, :email_addresses

  def setup
    @license = create_license
    @grant = create_grant(@license, User.find(2))
  end

  def test_token_has_32_bytes_and_only_digest_is_stored
    device, token = create_device(@grant)
    assert_equal 64, token.length
    assert_equal Digest::SHA256.hexdigest(token), device.token_digest
    assert_not_equal token, device.token_digest
    assert_equal device, MultirdpDevice.authenticate(token)
    assert_nil MultirdpDevice.authenticate(token.reverse)
    assert_nil MultirdpDevice.authenticate('')
    assert_nil MultirdpDevice.authenticate(nil)
  end

  def test_pending_expires_after_15_minutes
    device, = create_device(@grant)
    assert device.pending_open?
    device.update_columns(requested_at: 16.minutes.ago)
    assert device.pending_expired?
    assert_equal 'denied', device.effective_status
    assert_not device.approve!
    assert_equal 0, @grant.pending_devices.count
  end

  def test_state_transitions
    device, = create_device(@grant)
    assert device.approve!
    assert device.approved?
    assert device.approved_at.present?
    assert_not device.deny!
    assert device.revoke!
    assert device.revoked?
    assert_not device.revoke!
  end

  def test_mail_contains_approve_url
    device, = create_device(@grant)
    mail = MultirdpMailer.device_requested(User.find(2), device)
    assert_equal ['jsmith@somenet.foo'], mail.to
    assert_match(%r{/my/licenses}, mail.text_part.body.to_s)
    assert_match(/MacBook von Leander/, mail.subject)
  end
end
