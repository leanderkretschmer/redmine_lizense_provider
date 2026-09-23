# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class MultirdpMyLicensesControllerTest < Redmine::ControllerTest
  include MultirdpTestHelper
  fixtures :users, :email_addresses, :user_preferences

  def setup
    @license = create_license
    @grant = create_grant(@license, User.find(2))
    @device, = create_device(@grant)
    @request.session[:user_id] = 2
  end

  def test_requires_login
    @request.session[:user_id] = nil
    get :index
    assert_response 302
  end

  def test_index_shows_pending_and_no_secret_content
    @grant.store_secret!(SERVER_ID, "[Interface]\nPrivateKey = HIDDENKEY==\n")
    get :index
    assert_response :success
    assert_select 'h3', text: /multiRDP — Büro Hamburg/
    assert_select 'form[action=?]', approve_my_license_device_path(@device)
    assert_no_match(/HIDDENKEY/, response.body)
  end

  def test_approve_own_device
    post :approve_device, params: { id: @device.id }
    assert_redirected_to my_licenses_path
    assert_equal 'approved', @device.reload.status
    assert_equal 1, MultirdpEvent.where(action: 'device_approved', device_id: @device.id).count
  end

  def test_deny_own_device
    post :deny_device, params: { id: @device.id }
    assert_equal 'denied', @device.reload.status
  end

  def test_revoke_own_device
    @device.approve!
    post :revoke_device, params: { id: @device.id }
    assert_equal 'revoked', @device.reload.status
  end

  def test_cannot_touch_other_users_device
    @request.session[:user_id] = 3
    post :approve_device, params: { id: @device.id }
    assert_response 404
    assert_equal 'pending', @device.reload.status
  end

  def test_approval_box_on_other_pages
    get :index
    assert_select '#multirdp-approval', 0
  end
end
