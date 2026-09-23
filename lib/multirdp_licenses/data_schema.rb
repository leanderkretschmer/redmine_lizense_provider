# frozen_string_literal: true

module MultirdpLicenses
  # Normalisiert und prüft die beiden JSON-Bereiche einer Lizenz:
  # `data` (Vorgabe des Administrators) und `settings` (Einstellungen des
  # Benutzers). Die Feldnamen entsprechen dem Modell der App (Abschnitt 5).
  module DataSchema
    SERVER_FIELDS = %w[id name host port username domain vpnMode vpnEndpoint].freeze
    APP_FIELDS    = %w[id serverId name program arguments processName knownApplicationIds icon].freeze
    TRANSFER_FIELDS = {
      'maxApps' => :integer, 'autoReconnect' => :boolean, 'reconnectAttempts' => :integer,
      'sound' => :integer, 'microphone' => :boolean, 'clipboard' => :boolean,
      'multimon' => :boolean, 'shareMode' => :integer, 'scalePercent' => :integer
    }.freeze
    WORKSPACE_FIELDS = { 'saveOnQuit' => :boolean, 'restoreFromLink' => :boolean,
                         'savedAt' => :string_or_nil, 'items' => :array }.freeze
    SETTINGS_KEYS = %w[transfer workspace ownApps].freeze

    UUID_RE = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

    VPN_MODES   = (0..2)
    SHARE_MODES = (0..3)

    # Ein Fehler: Symbol für l(...) plus Platzhalter.
    Error = Struct.new(:key, :args) do
      def to_s
        return key.to_s if args.empty?

        "#{key}(#{args.map { |k, v| "#{k}=#{v}" }.join(', ')})"
      end

      # Übersetzter Text für die Oberfläche.
      def message
        ::I18n.t(key, **args, default: to_s)
      end
    end

    module_function

    def empty_data
      { 'servers' => [], 'apps' => [] }
    end

    def empty_settings
      { 'transfer' => {}, 'workspace' => {}, 'ownApps' => [] }
    end

    # ---- data --------------------------------------------------------------

    # Bringt eine (aus Formular oder JSON stammende) Struktur in die
    # kanonische Form. Unbekannte Felder werden verworfen.
    def normalize_data(raw)
      raw = {} unless raw.is_a?(Hash)
      servers = Array(raw['servers'] || raw[:servers]).map { |s| normalize_server(s) }
      apps    = Array(raw['apps'] || raw[:apps]).map { |a| normalize_app(a) }
      { 'servers' => servers, 'apps' => apps }
    end

    def normalize_server(s)
      s = s.respond_to?(:to_unsafe_h) ? s.to_unsafe_h : (s.is_a?(Hash) ? s : {})
      s = s.stringify_keys
      {
        'id'          => s['id'].to_s.strip.downcase.presence || SecureRandom.uuid,
        'name'        => s['name'].to_s.strip,
        'host'        => s['host'].to_s.strip,
        'port'        => to_int(s['port'], 0),
        'username'    => s['username'].to_s.strip,
        'domain'      => s['domain'].to_s.strip,
        'vpnMode'     => to_int(s['vpnMode'], 0),
        'vpnEndpoint' => s['vpnEndpoint'].to_s.strip
      }
    end

    def normalize_app(a)
      a = a.respond_to?(:to_unsafe_h) ? a.to_unsafe_h : (a.is_a?(Hash) ? a : {})
      a = a.stringify_keys
      known = a['knownApplicationIds']
      known = known.to_s.split(',') if known.is_a?(String)
      icon = a['icon']
      icon = nil if icon.is_a?(String) && icon.strip.empty?
      {
        'id'                  => a['id'].to_s.strip.downcase.presence || SecureRandom.uuid,
        'serverId'            => a['serverId'].to_s.strip.downcase,
        'name'                => a['name'].to_s.strip,
        'program'             => a['program'].to_s.strip,
        'arguments'           => a['arguments'].to_s,
        'processName'         => a['processName'].to_s.strip,
        'knownApplicationIds' => Array(known).map { |k| k.to_s.strip }.reject(&:empty?),
        'icon'                => icon.is_a?(String) ? icon : nil
      }
    end

    # Liefert eine Liste von Error; leer = gültig.
    def validate_data(data)
      errors = []
      unless data.is_a?(Hash) && data['servers'].is_a?(Array) && data['apps'].is_a?(Array)
        return [Error.new(:multirdp_error_data_structure, {})]
      end

      ids = Hash.new(0)
      server_ids = []
      data['servers'].each_with_index do |s, i|
        n = i + 1
        errors << Error.new(:multirdp_error_server_id, { n: n })       unless s['id'].to_s.match?(UUID_RE)
        errors << Error.new(:multirdp_error_server_name, { n: n })     if s['name'].to_s.empty?
        errors << Error.new(:multirdp_error_server_host, { n: n })     if s['host'].to_s.empty?
        errors << Error.new(:multirdp_error_server_port, { n: n })     unless s['port'].is_a?(Integer) && (0..65_535).cover?(s['port'])
        errors << Error.new(:multirdp_error_server_vpn_mode, { n: n }) unless s['vpnMode'].is_a?(Integer) && VPN_MODES.cover?(s['vpnMode'])
        ids[s['id']] += 1
        server_ids << s['id']
      end

      data['apps'].each_with_index do |a, i|
        n = i + 1
        errors << Error.new(:multirdp_error_app_id, { n: n })      unless a['id'].to_s.match?(UUID_RE)
        errors << Error.new(:multirdp_error_app_name, { n: n })    if a['name'].to_s.empty?
        errors << Error.new(:multirdp_error_app_program, { n: n }) if a['program'].to_s.empty?
        errors << Error.new(:multirdp_error_app_server, { n: n })  unless server_ids.include?(a['serverId'])
        errors << Error.new(:multirdp_error_app_known_ids, { n: n }) unless a['knownApplicationIds'].is_a?(Array)
        errors.concat(validate_icon(a['icon'], n))
        ids[a['id']] += 1
      end

      ids.each { |id, count| errors << Error.new(:multirdp_error_duplicate_id, { id: id }) if count > 1 }
      errors
    end

    def validate_icon(icon, n)
      return [] if icon.nil?
      return [Error.new(:multirdp_error_app_icon, { n: n, reason: ::I18n.t(:multirdp_icon_bad_base64) })] unless icon.is_a?(String)

      result = IconValidator.check_base64(icon)
      result.ok? ? [] : [Error.new(:multirdp_error_app_icon, { n: n, reason: ::I18n.t(result.error) })]
    end

    # ---- settings ----------------------------------------------------------

    # Prüft die vom Client geschriebenen Einstellungen. Unbekannte Schlüssel
    # auf oberster Ebene werden abgewiesen; innerhalb der Bereiche werden nur
    # die bekannten Felder auf ihren Typ geprüft.
    def validate_settings(settings)
      return [Error.new(:multirdp_error_settings_structure, {})] unless settings.is_a?(Hash)

      errors = []
      (settings.keys - SETTINGS_KEYS).each { |k| errors << Error.new(:multirdp_error_settings_unknown_key, { key: k }) }

      transfer = settings['transfer']
      if transfer.nil? || transfer.is_a?(Hash)
        (transfer || {}).each do |k, v|
          type = TRANSFER_FIELDS[k]
          next if type.nil?
          errors << Error.new(:multirdp_error_settings_type, { field: "transfer.#{k}" }) unless type_ok?(v, type)
        end
        if transfer && transfer.key?('shareMode') && transfer['shareMode'].is_a?(Integer) && !SHARE_MODES.cover?(transfer['shareMode'])
          errors << Error.new(:multirdp_error_settings_type, { field: 'transfer.shareMode' })
        end
      else
        errors << Error.new(:multirdp_error_settings_type, { field: 'transfer' })
      end

      workspace = settings['workspace']
      if workspace.nil? || workspace.is_a?(Hash)
        (workspace || {}).each do |k, v|
          type = WORKSPACE_FIELDS[k]
          next if type.nil?
          errors << Error.new(:multirdp_error_settings_type, { field: "workspace.#{k}" }) unless type_ok?(v, type)
        end
        Array(workspace && workspace['items']).each_with_index do |item, i|
          unless item.is_a?(Hash) && item['appId'].is_a?(String) &&
                 item['serverRect'].is_a?(Array) && item['serverRect'].length == 4 &&
                 item['serverRect'].all? { |x| x.is_a?(Numeric) } &&
                 [true, false].include?(item['minimized']) && [true, false].include?(item['maximized'])
            errors << Error.new(:multirdp_error_settings_type, { field: "workspace.items[#{i}]" })
          end
        end
      else
        errors << Error.new(:multirdp_error_settings_type, { field: 'workspace' })
      end

      own = settings['ownApps']
      if own.nil? || own.is_a?(Array)
        Array(own).each_with_index do |a, i|
          unless a.is_a?(Hash)
            errors << Error.new(:multirdp_error_settings_type, { field: "ownApps[#{i}]" })
            next
          end
          errors << Error.new(:multirdp_error_settings_type, { field: "ownApps[#{i}].id" }) unless a['id'].to_s.match?(UUID_RE)
          errors << Error.new(:multirdp_error_settings_type, { field: "ownApps[#{i}].serverId" }) unless a['serverId'].is_a?(String)
          errors << Error.new(:multirdp_error_settings_type, { field: "ownApps[#{i}].name" }) unless a['name'].is_a?(String) && !a['name'].empty?
          errors << Error.new(:multirdp_error_settings_type, { field: "ownApps[#{i}].program" }) unless a['program'].is_a?(String)
          errors.concat(validate_icon(a['icon'], i + 1))
        end
      else
        errors << Error.new(:multirdp_error_settings_type, { field: 'ownApps' })
      end

      errors
    end

    def type_ok?(value, type)
      case type
      when :integer       then value.is_a?(Integer)
      when :boolean       then [true, false].include?(value)
      when :string_or_nil then value.nil? || value.is_a?(String)
      when :array         then value.is_a?(Array)
      else true
      end
    end

    def to_int(value, default)
      return default if value.nil? || value.to_s.strip.empty?

      Integer(value.to_s, 10)
    rescue ArgumentError, TypeError
      value
    end
  end
end
