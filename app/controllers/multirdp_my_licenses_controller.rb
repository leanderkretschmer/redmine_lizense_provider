# frozen_string_literal: true

# "Mein Konto" → Lizenzen: eigene Zuteilungen, Geräte, Freigabeanfragen.
# Ein Benutzer sieht und ändert nur seine eigenen Zuteilungen und Geräte;
# das wird hier im Controller geprüft (find_own_device), nicht in der Ansicht.
class MultirdpMyLicensesController < ApplicationController
  before_action :require_login
  before_action :find_own_device, only: [:approve_device, :deny_device, :revoke_device]

  helper :multirdp_licenses

  def index
    @grants = MultirdpGrant.for_user(User.current).includes(:license, :devices).order(:created_at)
    @pending_devices = MultirdpDevice.joins(:grant).where(multirdp_grants: { user_id: User.current.id })
                                     .pending_open.sorted
  end

  def approve_device
    if @device.approve!
      MultirdpEvent.record!(MultirdpEvent::DEVICE_APPROVED, grant: @device.grant, device: @device, ip: request.remote_ip,
                            detail: @device.to_s)
      flash[:notice] = l(:notice_multirdp_device_approved, name: @device.to_s)
    else
      flash[:error] = l(:error_multirdp_device_not_pending)
    end
    redirect_back_or_default my_licenses_path
  end

  def deny_device
    if @device.deny!
      MultirdpEvent.record!(MultirdpEvent::DEVICE_DENIED, grant: @device.grant, device: @device, ip: request.remote_ip,
                            detail: @device.to_s)
      flash[:notice] = l(:notice_multirdp_device_denied, name: @device.to_s)
    else
      flash[:error] = l(:error_multirdp_device_not_pending)
    end
    redirect_back_or_default my_licenses_path
  end

  def revoke_device
    if @device.revoke!
      MultirdpEvent.record!(MultirdpEvent::DEVICE_REVOKED, grant: @device.grant, device: @device, ip: request.remote_ip,
                            detail: @device.to_s)
      flash[:notice] = l(:notice_multirdp_device_revoked, name: @device.to_s)
    end
    redirect_back_or_default my_licenses_path
  end

  private

  def find_own_device
    @device = MultirdpDevice.joins(:grant).where(multirdp_grants: { user_id: User.current.id }).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end
end
