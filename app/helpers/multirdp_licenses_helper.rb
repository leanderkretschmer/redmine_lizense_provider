# frozen_string_literal: true

module MultirdpLicensesHelper
  def multirdp_grant_status_tag(grant)
    status = grant.effective_status
    content_tag(:span, grant.status_label, class: "multirdp-status multirdp-status-#{status}")
  end

  def multirdp_device_status_tag(device)
    status = device.effective_status
    content_tag(:span, device.status_label, class: "multirdp-status multirdp-status-#{status}")
  end

  def multirdp_vpn_mode_options
    (0..2).map { |m| [l(:"label_multirdp_vpn_mode_#{m}"), m] }
  end

  def multirdp_vpn_mode_label(mode)
    l(:"label_multirdp_vpn_mode_#{mode.to_i}", default: mode.to_s)
  end

  def multirdp_platform_label(platform)
    l(:"label_multirdp_platform_#{platform}", default: platform.to_s)
  end

  def multirdp_icon_tag(base64, size: 24)
    return '' if base64.blank?

    tag.img(src: "data:image/png;base64,#{base64}", width: size, height: size, class: 'multirdp-icon', alt: '')
  end

  def multirdp_time_ago(time)
    return '-' if time.nil?

    l(:label_multirdp_time_ago, time: distance_of_time_in_words(Time.now, time)) + " (#{format_time(time)})"
  end

  def multirdp_grace_days_label(license)
    l(:label_multirdp_grace_days_value, count: license.grace_days)
  end

  # Warnung in der Verwaltung, wenn nicht verschlüsselt werden kann.
  def multirdp_encryption_warning
    return '' if MultirdpLicenses::Encryption.ready?

    key = MultirdpLicenses::Encryption.problem == :too_short ? :text_multirdp_encryption_too_short : :text_multirdp_encryption_missing
    content_tag(:div, l(key, env: MultirdpLicenses::Encryption::ENV_NAME, file: MultirdpLicenses::Encryption.key_file_path,
                            min: MultirdpLicenses::Encryption::MIN_KEY_LENGTH), class: 'flash warning')
  end

  # Zeigt nur, ob RDP-Kennwörter hinterlegt sind — nie den Inhalt.
  def multirdp_rdp_password_summary(grant)
    ids = grant.rdp_password_server_ids
    return l(:label_multirdp_secret_none) if ids.empty?

    l(:label_multirdp_rdp_password_count, count: ids.size)
  end

  # Zeigt nur, ob eine VPN-Konfiguration hinterlegt ist — nie den Inhalt.
  def multirdp_secret_summary(grant)
    ids = grant.secret_server_ids
    return l(:label_multirdp_secret_none) if ids.empty?

    l(:label_multirdp_secret_count, count: ids.size)
  end
end
