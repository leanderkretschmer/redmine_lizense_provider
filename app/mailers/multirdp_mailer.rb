# frozen_string_literal: true

# E-Mail über Redmines eigenen Mailer, wenn ein Gerät um Freigabe bittet.
class MultirdpMailer < Mailer
  # Erstes Argument muss ein User sein (Redmine::Mailer#process).
  def device_requested(user, device)
    @device = device
    @user = user
    @approve_url = my_licenses_url(::Mailer.default_url_options)
    mail to: user.mail, subject: I18n.t(:mail_subject_multirdp_device_requested, name: device.to_s)
  end

  def self.deliver_device_requested(device)
    user = device.grant&.user
    return if user.nil? || user.mail.blank?

    device_requested(user, device).deliver_later
  rescue StandardError => e
    Rails.logger.error("[redmine_lizense_provider] Mailversand fehlgeschlagen: #{e.class}: #{e.message}") if Rails.logger
    nil
  end
end
