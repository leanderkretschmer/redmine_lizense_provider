# frozen_string_literal: true

# Verwaltung → Lizenzen (nur Administratoren).
class MultirdpLicensesController < ApplicationController
  layout 'admin'
  self.main_menu = false

  before_action :require_admin
  before_action :find_license, only: [:show, :edit, :update, :destroy, :data_json]

  helper :multirdp_licenses
  helper :users

  def index
    @licenses = MultirdpLicense.sorted.includes(:created_by).to_a
    @grant_counts = MultirdpGrant.group(:license_id).count
  end

  def show
    @grants = @license.grants.sorted.includes(:user, :devices)
    @user_query = params[:q].to_s.strip
    @candidates = candidate_users(@user_query)
  end

  def new
    @license = MultirdpLicense.new(grace_days: MultirdpLicenses::DEFAULT_GRACE_DAYS)
  end

  def create
    @license = MultirdpLicense.new
    @license.created_by = User.current
    assign_from_params(@license)
    if @license.errors.empty? && @license.save
      MultirdpEvent.record!(MultirdpEvent::LICENSE_CREATED, ip: request.remote_ip, detail: "license_id=#{@license.id} #{@license.name}")
      MultirdpEvent.record!(MultirdpEvent::RDP_PASSWORD_STORED, ip: request.remote_ip, detail: "license_id=#{@license.id}") if @rdp_password_changed
      flash[:notice] = l(:notice_successful_create)
      redirect_to multirdp_license_path(@license)
    else
      @license.validate if @license.errors.empty?
      render :new
    end
  end

  def edit; end

  def update
    assign_from_params(@license)
    if @license.errors.empty? && @license.save
      MultirdpEvent.record!(MultirdpEvent::LICENSE_UPDATED, ip: request.remote_ip,
                            detail: "license_id=#{@license.id} revision=#{@license.revision}")
      MultirdpEvent.record!(MultirdpEvent::RDP_PASSWORD_STORED, ip: request.remote_ip, detail: "license_id=#{@license.id}") if @rdp_password_changed
      flash[:notice] = l(:notice_successful_update)
      redirect_to multirdp_license_path(@license)
    else
      @license.validate if @license.errors.empty?
      render :edit
    end
  end

  def destroy
    name = @license.name
    @license.destroy
    MultirdpEvent.record!(MultirdpEvent::LICENSE_DELETED, ip: request.remote_ip, detail: name)
    flash[:notice] = l(:notice_successful_delete)
    redirect_to multirdp_licenses_path
  end

  # Ansicht des erzeugten JSON (Beiwerk).
  def data_json
    render plain: JSON.pretty_generate(@license.data), content_type: 'application/json'
  end

  private

  def find_license
    @license = MultirdpLicense.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def candidate_users(query)
    return [] if query.blank?

    granted_ids = @license.grants.pluck(:user_id)
    User.active.like(query).sorted.where.not(id: granted_ids).limit(25).to_a
  end

  # Keine Massenzuweisung: nur die ausdrücklich erlaubten Felder.
  def assign_from_params(license)
    attrs = params.fetch(:license, {})
    attrs = attrs.permit(:name, :notes, :grace_days) if attrs.respond_to?(:permit)
    license.safe_attributes = attrs.to_h
    license.data = build_data(license)
    apply_rdp_passwords(license)
  end

  # RDP-Kennwörter aus den Server-Zeilen: neues Kennwort setzen oder vorhandenes entfernen.
  def apply_rdp_passwords(license)
    hash_values(params.dig(:license, :servers)).each do |s|
      s = s.to_unsafe_h if s.respond_to?(:to_unsafe_h)
      server_id = s['id'].to_s.strip.downcase
      next if server_id.empty?

      if s['rdp_password'].to_s.present?
        if s['rdp_password'].to_s.bytesize > 255
          license.errors.add(:base, l(:error_multirdp_rdp_password_invalid))
          next
        end
        license.set_rdp_password(server_id, s['rdp_password'].to_s)
        @rdp_password_changed = true
      elsif s['rdp_password_remove'].to_s == '1'
        @rdp_password_changed = true if license.remove_rdp_password(server_id)
      end
    end
  rescue MultirdpLicenses::EncryptionUnavailable
    license.errors.add(:base, l(:error_multirdp_encryption_unavailable))
  end

  # Baut `data` aus dem Formular; Symbole werden hochgeladen oder übernommen.
  def build_data(license)
    servers_p = params.dig(:license, :servers)
    apps_p    = params.dig(:license, :apps)
    # Formular ohne Vorgabe-Teil (z. B. Tests, die nur den Namen ändern): Vorgabe unverändert lassen.
    return license.data if servers_p.nil? && apps_p.nil?

    existing_icons = license.apps.to_h { |a| [a['id'], a['icon']] }
    servers = hash_values(servers_p).map do |s|
      s = s.to_unsafe_h if s.respond_to?(:to_unsafe_h)
      s.slice(*MultirdpLicenses::DataSchema::SERVER_FIELDS)
    end
    apps = hash_values(apps_p).map do |a|
      a = a.to_unsafe_h if a.respond_to?(:to_unsafe_h)
      app = a.slice(*(MultirdpLicenses::DataSchema::APP_FIELDS - ['icon']))
      app['icon'] = icon_for(a, existing_icons)
      app
    end
    { 'servers' => servers, 'apps' => apps }
  end

  # Neues Symbol hochgeladen → prüfen; sonst vorhandenes behalten oder entfernen.
  def icon_for(app_params, existing_icons)
    upload = app_params['icon_file']
    if upload.respond_to?(:read)
      bytes = upload.read
      result = MultirdpLicenses::IconValidator.check_bytes(bytes)
      return MultirdpLicenses::IconValidator.encode(bytes) if result.ok?

      # Ungültiges Symbol: Base64 durchreichen, damit die Modellprüfung den Fehler meldet.
      return MultirdpLicenses::IconValidator.encode(bytes)
    end
    return nil if app_params['icon_remove'].to_s == '1'

    existing_icons[app_params['id'].to_s.downcase]
  end

  def hash_values(value)
    return [] if value.blank?

    value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
    value.is_a?(Hash) ? value.values : Array(value)
  end
end
