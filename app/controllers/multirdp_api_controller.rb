# frozen_string_literal: true

# Schnittstelle für den multiRDP-Client: /multirdp/api/v1/…
#
# Alles JSON, nur über HTTPS, Authentifizierung ausschließlich über das
# Gerätetoken (Authorization: Bearer …). Das Token ist kein Redmine-API-Schlüssel
# und öffnet keinen anderen Teil von Redmine; Redmines eigene Anmeldefilter
# werden hier deshalb bewusst nicht durchlaufen.
class MultirdpApiController < ApplicationController
  # Redmine-Filter, die eine Browser-Sitzung voraussetzen, abschalten.
  skip_before_action :session_expiration, :user_setup, :check_if_login_required,
                     :set_localization, :check_password_change, :check_twofa_activation
  skip_before_action :verify_authenticity_token

  before_action :force_json
  before_action :require_https
  before_action :reset_current_user
  before_action :authenticate_device, except: [:create_session]
  before_action :require_usable_grant, only: [:show_license, :update_settings, :update_data, :show_secret, :show_rdp_password]

  rescue_from ActionController::ParameterMissing do |e|
    api_error(400, 'ungueltige_anfrage', parameter: e.param.to_s)
  end
  rescue_from ActiveRecord::RecordNotFound do
    api_error(404, 'nicht_gefunden')
  end
  rescue_from ActiveRecord::RecordInvalid do |e|
    api_error(422, 'ungueltige_anfrage', detail: e.record.errors.full_messages)
  end

  # POST /multirdp/api/v1/session
  def create_session
    ip = request.remote_ip
    return api_error(429, 'zu_viele_versuche') if MultirdpLicenses::RateLimiter.exceeded?(ip)

    login    = params.require(:login).to_s
    password = params.require(:password).to_s
    device_p = params.require(:device)
    device_p = device_p.permit(:name, :platform, :app_version, :public_key) if device_p.respond_to?(:permit)

    user = User.try_to_login(login, password)
    MultirdpEvent.record!(MultirdpEvent::LOGIN_ATTEMPT, user: user, ip: ip,
                          detail: user ? "ok login=#{login.first(100)}" : "failed login=#{login.first(100)}")
    return api_error(401, 'anmeldung_fehlgeschlagen') if user.nil?

    grant = MultirdpGrant.effective_for(user)
    return api_error(403, 'keine_lizenz') if grant.nil?

    open_count = MultirdpDevice.joins(:grant).where(multirdp_grants: { user_id: user.id }).pending_open.count
    return api_error(429, 'zu_viele_anfragen') if open_count >= MultirdpLicenses::MAX_PENDING_PER_USER

    platform = device_p[:platform].to_s.downcase
    return api_error(422, 'ungueltige_anfrage', parameter: 'device.platform') unless MultirdpLicenses::PLATFORMS.include?(platform)

    device, token = MultirdpDevice.register!(
      grant: grant,
      name: device_p[:name].presence || 'multiRDP',
      platform: platform,
      app_version: device_p[:app_version],
      public_key: device_p[:public_key],
      ip: ip
    )
    MultirdpEvent.record!(MultirdpEvent::DEVICE_REQUESTED, user: user, grant: grant, device: device, ip: ip,
                          detail: "#{device.name} (#{device.platform} #{device.app_version})")
    MultirdpMailer.deliver_device_requested(device)

    render json: { token: token, status: device.status, approve_url: approve_url }
  end

  # DELETE /multirdp/api/v1/session
  def destroy_session
    @device.revoke!
    MultirdpEvent.record!(MultirdpEvent::SESSION_ENDED, user: @device.grant.user, grant: @device.grant,
                          device: @device, ip: request.remote_ip)
    render json: { status: @device.status }
  end

  # GET /multirdp/api/v1/license
  def show_license
    license = @grant.license
    etag = [license.id, license.revision, @grant.settings_revision, @grant.updated_at.to_i, @device.id]
    return unless stale?(etag: etag, public: false)

    render json: {
      status: 'active',
      license: { id: license.id, name: license.name, valid_until: @grant.valid_until&.iso8601 },
      revision: license.revision,
      settings_revision: @grant.settings_revision,
      grace_days: license.grace_days,
      data: license.data,
      settings: @grant.settings,
      secrets_available: @grant.secret_server_ids,
      rdp_passwords_available: @grant.rdp_password_server_ids
    }
  end

  # PUT /multirdp/api/v1/settings
  def update_settings
    return api_error(403, 'data_schreibgeschuetzt') if params.key?(:data)

    expected = params.require(:settings_revision)
    incoming = params.require(:settings)
    incoming = incoming.to_unsafe_h if incoming.respond_to?(:to_unsafe_h)
    incoming = incoming.deep_stringify_keys if incoming.is_a?(Hash)

    if incoming.to_json.bytesize > MultirdpLicenses::MAX_SETTINGS_BYTES
      return api_error(413, 'ungueltige_einstellungen', detail: ['zu groß / too large'])
    end

    schema_errors = MultirdpLicenses::DataSchema.validate_settings(incoming)
    return api_error(422, 'ungueltige_einstellungen', detail: schema_errors.map(&:to_s)) if schema_errors.any?

    unless @grant.write_settings!(incoming, expected)
      @grant.reload
      return render json: { error: 'revision_konflikt', settings_revision: @grant.settings_revision,
                            settings: @grant.settings }, status: 409
    end

    MultirdpEvent.record!(MultirdpEvent::SETTINGS_WRITTEN, user: @grant.user, grant: @grant, device: @device,
                          ip: request.remote_ip, detail: "settings_revision=#{@grant.settings_revision}")
    render json: { settings_revision: @grant.settings_revision }
  end

  # PUT/PATCH/POST /multirdp/api/v1/data — gibt es nicht; `data` gehört dem Administrator.
  def update_data
    api_error(403, 'data_schreibgeschuetzt')
  end

  # GET /multirdp/api/v1/secrets/:server_id
  def show_secret
    server_id = params[:server_id].to_s.downcase
    config = @grant.secret_for(server_id)
    return api_error(404, 'kein_geheimnis') if config.nil?

    MultirdpEvent.record!(MultirdpEvent::SECRET_FETCHED, user: @grant.user, grant: @grant, device: @device,
                          ip: request.remote_ip, detail: "server_id=#{server_id}")
    response.headers['Cache-Control'] = 'no-store'
    render plain: config, content_type: 'text/plain; charset=utf-8'
  end

  # GET /multirdp/api/v1/secrets/:server_id/rdp — RDP-Kennwort des Servers (Erweiterung, siehe README).
  def show_rdp_password
    server_id = params[:server_id].to_s.downcase
    password = @grant.rdp_password_for(server_id)
    return api_error(404, 'kein_geheimnis') if password.nil?

    MultirdpEvent.record!(MultirdpEvent::RDP_PASSWORD_FETCHED, user: @grant.user, grant: @grant, device: @device,
                          ip: request.remote_ip, detail: "server_id=#{server_id}")
    response.headers['Cache-Control'] = 'no-store'
    render json: { server_id: server_id, password: password }
  end

  private

  def force_json
    request.format = :json
  end

  # Abweisen, nicht umleiten.
  def require_https
    return if request.ssl?

    api_error(403, 'https_erforderlich')
  end

  def reset_current_user
    User.current = User.anonymous
  end

  def bearer_token
    header = request.authorization.to_s
    return nil unless header =~ /\ABearer\s+(\S+)\z/i

    Regexp.last_match(1)
  end

  def authenticate_device
    @device = MultirdpDevice.authenticate(bearer_token)
    return api_error(401, 'token_ungueltig') if @device.nil?

    @device.touch_seen!(request.remote_ip)
    @grant = @device.grant
    User.current = @grant.user if @grant.user&.active?
  end

  # Zuteilung und Gerät müssen benutzbar sein; sonst 202 (pending) oder 403 mit Grund.
  def require_usable_grant
    if (reason = @grant.denial_reason)
      return api_error(403, reason)
    end

    if @device.pending_expired?
      @device.deny!
      MultirdpEvent.record!(MultirdpEvent::DEVICE_EXPIRED, user: @grant.user, grant: @grant, device: @device,
                            ip: request.remote_ip)
    end

    case @device.status
    when MultirdpDevice::STATUS_PENDING
      render json: { status: 'pending' }, status: 202
    when MultirdpDevice::STATUS_APPROVED
      true
    else
      api_error(403, 'geraet_gesperrt')
    end
  end

  def approve_url
    my_licenses_url(::Mailer.default_url_options)
  rescue StandardError
    "#{Setting.protocol}://#{Setting.host_name}/my/licenses"
  end

  def api_error(status, code, extra = {})
    render json: { error: code }.merge(extra), status: status
    false
  end
end
