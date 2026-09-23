# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class MultirdpLicenseTest < ActiveSupport::TestCase
  include MultirdpTestHelper
  fixtures :users, :email_addresses

  def test_defaults
    license = MultirdpLicense.create!(name: 'Test')
    assert_equal 'multirdp', license.kind
    assert_equal 1, license.revision
    assert_equal 14, license.grace_days
    assert_equal({ 'servers' => [], 'apps' => [] }, license.data)
  end

  def test_revision_increases_on_data_change_only
    license = create_license
    assert_equal 1, license.revision
    license.update!(notes: 'nur Notizen')
    assert_equal 1, license.reload.revision
    data = license.data
    data['servers'][0]['host'] = '10.0.0.1'
    license.data = data
    license.save!
    assert_equal 2, license.reload.revision
    assert_equal '10.0.0.1', license.servers.first['host']
  end

  def test_data_validation
    license = MultirdpLicense.new(name: 'x')
    license.data = { 'servers' => [{ 'id' => SERVER_ID, 'name' => '', 'host' => '', 'port' => 70_000, 'vpnMode' => 5 }],
                     'apps' => [{ 'id' => APP_ID, 'serverId' => 'nope', 'name' => '', 'program' => '' }] }
    assert_not license.valid?
    messages = license.errors[:data].join(' ')
    assert_match(/Server 1/, messages)
    assert_match(/RemoteApp 1/, messages)
  end

  def test_icon_validation
    license = MultirdpLicense.new(name: 'x')
    license.data = sample_data(icon: png_base64(64, 64))
    assert license.valid?, license.errors.full_messages.join(', ')

    license.data = sample_data(icon: png_base64(64, 32))
    assert_not license.valid?
    assert_match(/Symbol|icon/i, license.errors[:data].join(' '))
  end

  def test_ids_are_generated_and_normalized
    license = MultirdpLicense.new(name: 'x')
    license.data = { 'servers' => [{ 'name' => 'a', 'host' => 'b' }], 'apps' => [] }
    assert_match MultirdpLicenses::DataSchema::UUID_RE, license.servers.first['id']
    assert_equal 0, license.servers.first['port']
    assert_equal '', license.servers.first['domain']
  end

  def test_duplicate_ids_rejected
    license = MultirdpLicense.new(name: 'x')
    data = sample_data
    data['apps'][1]['id'] = APP_ID
    license.data = data
    assert_not license.valid?
  end
end
