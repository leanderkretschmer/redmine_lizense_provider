# frozen_string_literal: true

RedmineApp::Application.routes.draw do
  # ---- Schnittstelle für den Client (Abschnitt 6) ------------------------
  scope 'multirdp/api/v1', controller: 'multirdp_api', defaults: { format: 'json' } do
    post   'session',            action: 'create_session',  as: 'multirdp_api_session'
    delete 'session',            action: 'destroy_session'
    get    'license',            action: 'show_license',    as: 'multirdp_api_license'
    put    'settings',           action: 'update_settings', as: 'multirdp_api_settings'
    patch  'settings',           action: 'update_settings'
    match  'data',               action: 'update_data',     via: [:put, :patch, :post, :delete], as: 'multirdp_api_data'
    get    'secrets/:server_id', action: 'show_secret',     as: 'multirdp_api_secret'
  end

  # ---- "Mein Konto" → Lizenzen (Abschnitt 11) ----------------------------
  get  'my/licenses', to: 'multirdp_my_licenses#index', as: 'my_licenses'
  post 'my/licenses/devices/:id/approve', to: 'multirdp_my_licenses#approve_device', as: 'approve_my_license_device'
  post 'my/licenses/devices/:id/deny',    to: 'multirdp_my_licenses#deny_device',    as: 'deny_my_license_device'
  post 'my/licenses/devices/:id/revoke',  to: 'multirdp_my_licenses#revoke_device',  as: 'revoke_my_license_device'

  # ---- Verwaltung (Abschnitt 11) -----------------------------------------
  scope 'admin/multirdp' do
    resources :licenses, controller: 'multirdp_licenses', as: 'multirdp_licenses' do
      member do
        get 'data', action: 'data_json', as: 'data'
      end
    end
    post 'licenses/:license_id/grants', to: 'multirdp_grants#create', as: 'multirdp_license_grants'
    resources :grants, controller: 'multirdp_grants', as: 'multirdp_grants', only: [:show, :update, :destroy] do
      member do
        post   'secrets',            action: 'store_secret',  as: 'secrets'
        delete 'secrets/:server_id', action: 'delete_secret', as: 'secret'
      end
    end
    post 'devices/:id/revoke', to: 'multirdp_grants#revoke_device', as: 'revoke_multirdp_device'
  end
end
