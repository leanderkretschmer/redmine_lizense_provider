# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class MultirdpLicensesControllerTest < Redmine::ControllerTest
  include MultirdpTestHelper
  fixtures :users, :email_addresses, :user_preferences

  def setup
    @request.session[:user_id] = 1
  end

  def test_requires_admin
    @request.session[:user_id] = 2
    get :index
    assert_response 403
    get :new
    assert_response 403
  end

  def test_index
    create_license
    get :index
    assert_response :success
    assert_select 'table.list td.name a', text: 'multiRDP — Büro Hamburg'
  end

  def test_create_with_servers_and_apps
    png = Rack::Test::UploadedFile.new(StringIO.new(build_png(32, 32)), 'image/png', original_filename: 'icon.png')
    assert_difference 'MultirdpLicense.count' do
      post :create, params: {
        license: {
          name: 'Neu', notes: 'n', grace_days: 7,
          servers: { '0' => { id: SERVER_ID, name: 'srv', host: 'h', port: '0', username: 'u', domain: '', vpnMode: '1', vpnEndpoint: 'vpn:51820' } },
          apps: { '0' => { id: APP_ID, serverId: SERVER_ID, name: 'Revit', program: 'C:\\r.exe', arguments: '', processName: 'r.exe', knownApplicationIds: '', icon_file: png },
                  '1' => { id: APP2_ID, serverId: SERVER_ID, name: 'Excel', program: 'C:\\e.exe', arguments: '', processName: 'e.exe', knownApplicationIds: 'a, b' } }
        }
      }
    end
    license = MultirdpLicense.order(:id).last
    assert_redirected_to multirdp_license_path(license)
    assert_equal 7, license.grace_days
    assert_equal 1, license.servers.size
    assert_equal 2, license.apps.size
    assert_equal 0, license.servers.first['port']
    assert license.apps.first['icon'].present?
    assert_nil license.apps.last['icon']
    assert_equal %w[a b], license.apps.last['knownApplicationIds']
    assert_equal 1, MultirdpEvent.where(action: 'license_created').count
  end

  def test_create_rejects_bad_icon
    png = Rack::Test::UploadedFile.new(StringIO.new(build_png(32, 16)), 'image/png', original_filename: 'icon.png')
    assert_no_difference 'MultirdpLicense.count' do
      post :create, params: {
        license: {
          name: 'Neu',
          servers: { '0' => { id: SERVER_ID, name: 'srv', host: 'h' } },
          apps: { '0' => { id: APP_ID, serverId: SERVER_ID, name: 'Revit', program: 'x', icon_file: png } }
        }
      }
    end
    assert_response :success
    assert_select '#errorExplanation'
  end

  def test_update_bumps_revision_and_keeps_icon
    license = create_license
    license.data = sample_data(icon: png_base64)
    license.save!
    old_icon = license.apps.first['icon']
    patch :update, params: {
      id: license.id,
      license: {
        name: license.name,
        servers: { '0' => { id: SERVER_ID, name: 'srv', host: '10.0.0.9', port: '3389', vpnMode: '2' } },
        apps: { '0' => { id: APP_ID, serverId: SERVER_ID, name: 'Revit', program: 'x' },
                '1' => { id: APP2_ID, serverId: SERVER_ID, name: 'Excel', program: 'y', icon_remove: '1' } }
      }
    }
    assert_redirected_to multirdp_license_path(license)
    license.reload
    assert_equal 3, license.revision # 1 anlegen, 2 Symbol setzen, 3 Formular
    assert_equal '10.0.0.9', license.servers.first['host']
    assert_equal old_icon, license.apps.first['icon']
    assert_nil license.apps.last['icon']
  end

  def test_show_with_user_search_and_grant
    license = create_license
    get :show, params: { id: license.id, q: 'smith' }
    assert_response :success
    assert_select 'input[name=?][value=?]', 'user_ids[]', '2'
  end

  def test_data_json
    license = create_license
    get :data_json, params: { id: license.id }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal SERVER_ID, json['servers'].first['id']
  end

  def test_destroy
    license = create_license
    assert_difference 'MultirdpLicense.count', -1 do
      delete :destroy, params: { id: license.id }
    end
  end
end
