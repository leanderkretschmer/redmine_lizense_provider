# frozen_string_literal: true

# Verwaltung → Lizenzen → Zuteilungen (nur Administratoren).
class MultirdpGrantsController < ApplicationController
  layout 'admin'
  self.main_menu = false

  before_action :require_admin
  before_action :find_license, only: [:create]
  before_action :find_grant, only: [:show, :update, :destroy, :store_secret, :delete_secret, :store_rdp_password, :delete_rdp_password]
  before_action :find_device, only: [:revoke_device]

  helper :multirdp_licenses

  # POST /admin/multirdp/licenses/:license_id/grants — mehrere Benutzer auf einmal.
  def create
    user_ids = Array(params[:user_ids]).map(&:to_i).uniq
    valid_until = parse_date(params[:valid_until])
    created = 0
    failed = []
    User.active.where(id: user_ids).find_each do |user|
      grant = @license.grants.build(user: user, status: MultirdpGrant::STATUS_ACTIVE, valid_until: valid_until)
      if grant.save
        created += 1
        MultirdpEvent.record!(MultirdpEvent::GRANT_CREATED, grant: grant, ip: request.remote_ip,
                              detail: "user=#{user.login} valid_until=#{valid_until}")
      else
        failed << "#{user.name}: #{grant.errors.full_messages.join(', ')}"
      end
    end
    flash[:notice] = l(:notice_multirdp_grants_created, count: created) if created.positive?
    flash[:error] = failed.join('; ') if failed.any?
    redirect_to multirdp_license_path(@license)
  end

  def show
    @license = @grant.license
    @devices = @grant.devices.sorted
    @events  = @grant.events.sorted.includes(:user, :device).limit(200)
    @encryption_ready = MultirdpLicenses::Encryption.ready?
  end

  # PATCH /admin/multirdp/grants/:id — Zustand und Befristung.
  def update
    attrs = params.fetch(:grant, {})
    attrs = attrs.permit(:status, :valid_until) if attrs.respond_to?(:permit)
    attrs = attrs.to_h
    changes = {}
    changes[:status] = attrs['status'] if attrs.key?('status') && MultirdpGrant::STATUSES.include?(attrs['status'])
    changes[:valid_until] = parse_date(attrs['valid_until']) if attrs.key?('valid_until')

    if @grant.update(changes)
      action = changes[:status] == MultirdpGrant::STATUS_REVOKED ? MultirdpEvent::GRANT_REVOKED : MultirdpEvent::GRANT_UPDATED
      MultirdpEvent.record!(action, grant: @grant, ip: request.remote_ip, detail: changes.map { |k, v| "#{k}=#{v}" }.join(' '))
      flash[:notice] = l(:notice_successful_update)
    else
      flash[:error] = @grant.errors.full_messages.join(', ')
    end
    redirect_back_or_default multirdp_grant_path(@grant)
  end

  def destroy
    license = @grant.license
    MultirdpEvent.record!(MultirdpEvent::GRANT_DELETED, ip: request.remote_ip,
                          detail: "user=#{@grant.user&.login} license_id=#{license.id}")
    @grant.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to multirdp_license_path(license)
  end

  # POST /admin/multirdp/grants/:id/secrets — WireGuard-Konfiguration hinterlegen oder ersetzen.
  def store_secret
    server_id = params[:server_id].to_s.downcase
    unless @grant.license.server(server_id)
      flash[:error] = l(:error_multirdp_unknown_server)
      return redirect_to multirdp_grant_path(@grant)
    end

    config = params[:wireguard_file].respond_to?(:read) ? params[:wireguard_file].read : params[:wireguard_config].to_s
    config = config.to_s.encode('UTF-8', invalid: :replace, undef: :replace).strip
    if config.empty? || config.bytesize > 64.kilobytes
      flash[:error] = l(:error_multirdp_secret_invalid)
      return redirect_to multirdp_grant_path(@grant)
    end

    @grant.store_secret!(server_id, config)
    MultirdpEvent.record!(MultirdpEvent::SECRET_STORED, grant: @grant, ip: request.remote_ip, detail: "server_id=#{server_id}")
    flash[:notice] = l(:notice_multirdp_secret_stored)
    redirect_to multirdp_grant_path(@grant)
  rescue MultirdpLicenses::EncryptionUnavailable
    flash[:error] = l(:error_multirdp_encryption_unavailable)
    redirect_to multirdp_grant_path(@grant)
  end

  # DELETE /admin/multirdp/grants/:id/secrets/:server_id
  def delete_secret
    server_id = params[:server_id].to_s.downcase
    if @grant.delete_secret!(server_id)
      MultirdpEvent.record!(MultirdpEvent::SECRET_DELETED, grant: @grant, ip: request.remote_ip, detail: "server_id=#{server_id}")
      flash[:notice] = l(:notice_successful_delete)
    end
    redirect_to multirdp_grant_path(@grant)
  end

  # POST /admin/multirdp/grants/:id/rdp_password — RDP-Kennwort je Server hinterlegen oder ersetzen.
  def store_rdp_password
    server_id = params[:server_id].to_s.downcase
    unless @grant.license.server(server_id)
      flash[:error] = l(:error_multirdp_unknown_server)
      return redirect_to multirdp_grant_path(@grant)
    end

    password = params[:rdp_password].to_s
    if password.empty? || password.bytesize > 255
      flash[:error] = l(:error_multirdp_rdp_password_invalid)
      return redirect_to multirdp_grant_path(@grant)
    end

    @grant.store_rdp_password!(server_id, password)
    MultirdpEvent.record!(MultirdpEvent::RDP_PASSWORD_STORED, grant: @grant, ip: request.remote_ip, detail: "server_id=#{server_id}")
    flash[:notice] = l(:notice_multirdp_rdp_password_stored)
    redirect_to multirdp_grant_path(@grant)
  rescue MultirdpLicenses::EncryptionUnavailable
    flash[:error] = l(:error_multirdp_encryption_unavailable)
    redirect_to multirdp_grant_path(@grant)
  end

  # DELETE /admin/multirdp/grants/:id/rdp_password/:server_id
  def delete_rdp_password
    server_id = params[:server_id].to_s.downcase
    if @grant.delete_rdp_password!(server_id)
      MultirdpEvent.record!(MultirdpEvent::RDP_PASSWORD_DELETED, grant: @grant, ip: request.remote_ip, detail: "server_id=#{server_id}")
      flash[:notice] = l(:notice_successful_delete)
    end
    redirect_to multirdp_grant_path(@grant)
  end

  # POST /admin/multirdp/devices/:id/revoke
  def revoke_device
    if @device.revoke!
      MultirdpEvent.record!(MultirdpEvent::DEVICE_REVOKED, grant: @device.grant, device: @device, ip: request.remote_ip,
                            detail: "#{@device} (admin)")
      flash[:notice] = l(:notice_multirdp_device_revoked, name: @device.to_s)
    end
    redirect_back_or_default multirdp_grant_path(@device.grant)
  end

  private

  def find_license
    @license = MultirdpLicense.find(params[:license_id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_grant
    @grant = MultirdpGrant.includes(:license, :user).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_device
    @device = MultirdpDevice.includes(grant: :license).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
