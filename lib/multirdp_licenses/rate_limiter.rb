# frozen_string_literal: true

module MultirdpLicenses
  # Begrenzung der Anmeldeversuche je IP auf POST /multirdp/api/v1/session.
  # Zählt über multirdp_events (Aktion "login_attempt"), damit die Grenze auch
  # bei mehreren Anwendungsprozessen gilt und nicht vom Cache-Store abhängt.
  module RateLimiter
    module_function

    def exceeded?(ip)
      attempts(ip) >= LOGIN_ATTEMPTS_PER_HOUR
    end

    def attempts(ip)
      MultirdpEvent.where(action: MultirdpEvent::LOGIN_ATTEMPT, ip: ip.to_s)
                   .where('created_at > ?', 1.hour.ago).count
    end
  end
end
