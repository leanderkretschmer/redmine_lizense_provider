# frozen_string_literal: true

require 'base64'

module MultirdpLicenses
  # Prüft ein RemoteApp-Symbol: PNG, quadratisch, höchstens 1024×1024,
  # höchstens 256 KiB. Zu große Bilder werden abgewiesen, nicht beschnitten.
  module IconValidator
    MAX_BYTES = 256 * 1024
    MAX_EDGE  = 1024
    PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b

    Result = Struct.new(:ok, :error, :width, :height) do
      def ok?
        ok
      end
    end

    module_function

    # bytes: rohe PNG-Daten. Liefert Result.
    def check_bytes(bytes)
      bytes = bytes.to_s.b
      return Result.new(false, :multirdp_icon_not_png) unless bytes.start_with?(PNG_SIGNATURE)
      return Result.new(false, :multirdp_icon_too_large) if bytes.bytesize > MAX_BYTES
      return Result.new(false, :multirdp_icon_not_png) unless bytes.byteslice(12, 4) == 'IHDR'

      width, height = bytes.byteslice(16, 8).unpack('NN')
      return Result.new(false, :multirdp_icon_not_square, width, height) unless width == height
      return Result.new(false, :multirdp_icon_too_big, width, height) if width > MAX_EDGE || width.zero?

      Result.new(true, nil, width, height)
    end

    # base64: Base64-Text wie in data/settings gespeichert.
    def check_base64(base64)
      bytes = Base64.strict_decode64(base64.to_s)
      check_bytes(bytes)
    rescue ArgumentError
      Result.new(false, :multirdp_icon_bad_base64)
    end

    def encode(bytes)
      Base64.strict_encode64(bytes.to_s.b)
    end
  end
end
