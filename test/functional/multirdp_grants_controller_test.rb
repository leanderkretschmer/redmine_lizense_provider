# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class MultirdpGrantsControllerTest < Redmine::ControllerTest
  include MultirdpTestHelper
  fixtures :users, :email_addresses, :user_preferences

  def setup
    @request.session[:user_id] = 1
    @license = create_license
  end

  def test_requires_admin
    @request.session[:user_id] = 2
    post :create, params: { license_id: @license.id, user_ids: [2] }
    assert_response 403
  end

  def test_create_multiple_grants
    assert_difference 'MultirdpGrant.count', 2 do
      post :create, params: { license_id: @license.id, user_ids: [2, 3], valid_until: '2027-12-31' }
    end
    assert_redirected_to multirdp_license_path(@license)
    assert_equal Date.new(2027, 12, 31), @license.grants.find_by(user_id: 2).valid_until
  end

  def test_update_status_only_from_allowed_values
    grant = create_grant(@license, User.find(2))
    patch :update, params: { id: grant.id, grant: { status: 'bogus', valid_until: '' } }
    assert_equal 'active', grant.reload.status
    patch :update, params: { id: grant.id, grant: { status: 'revoked' } }
    assert_equal 'revoked', grant.reload.status
    assert_equal 1, MultirdpEvent.where(action: 'grant_revoked', grant_id: grant.id).count
  end

  def test_mass_assignment_is_blocked
    grant = create_grant(@license, User.find(2))
    patch :update, params: { id: grant.id, grant: { status: 'suspended', user_id: 3, settings_revision: 99 } }
    grant.reload
    assert_equal 2, grant.user_id
    assert_equal 0, grant.settings_revision
    assert_equal 'suspended', grant.status
  end

  def test_show_never_reveals_secret
    grant = create_grant(@license, User.find(2))
    grant.store_secret!(SERVER_ID, "[Interface]\nPrivateKey = HIDDENKEY==\n")
    get :show, params: { id: grant.id }
    assert_response :success
    assert_no_match(/HIDDENKEY/, response.body)
    assert_select '.multirdp-secret', /hinterlegt|stored/
  end

  def test_store_and_delete_secret
    grant = create_grant(@license, User.find(2))
    post :store_secret, params: { id: grant.id, server_id: SERVER_ID, wireguard_config: "[Interface]\nPrivateKey = X==\n" }
    assert_redirected_to multirdp_grant_path(grant)
    assert_equal "[Interface]\nPrivateKey = X==", grant.reload.secret_for(SERVER_ID)
    assert_equal 1, MultirdpEvent.where(action: 'secret_stored').count
    assert_no_match(/PrivateKey/, MultirdpEvent.last.detail.to_s)

    delete :delete_secret, params: { id: grant.id, server_id: SERVER_ID }
    assert_nil grant.reload.secret_for(SERVER_ID)
  end

  def test_store_secret_for_unknown_server
    grant = create_grant(@license, User.find(2))
    post :store_secret, params: { id: grant.id, server_id: 'ffffffff-0000-0000-0000-000000000000', wireguard_config: 'x' }
    assert_redirected_to multirdp_grant_path(grant)
    assert_nil grant.reload.secret_for('ffffffff-0000-0000-0000-000000000000')
  end

  def test_admin_revokes_device
    grant = create_grant(@license, User.find(2))
    device, = create_device(grant, status: 'approved')
    post :revoke_device, params: { id: device.id }
    assert_equal 'revoked', device.reload.status
  end
end
