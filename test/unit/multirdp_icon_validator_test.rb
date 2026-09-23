# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class MultirdpIconValidatorTest < ActiveSupport::TestCase
  include MultirdpTestHelper

  def test_accepts_square_png
    result = MultirdpLicenses::IconValidator.check_bytes(build_png(128, 128))
    assert result.ok?
    assert_equal 128, result.width
  end

  def test_rejects_non_square
    result = MultirdpLicenses::IconValidator.check_bytes(build_png(128, 64))
    assert_not result.ok?
    assert_equal :multirdp_icon_not_square, result.error
  end

  def test_rejects_too_big_edge
    result = MultirdpLicenses::IconValidator.check_bytes(build_png(1025, 1025))
    assert_not result.ok?
    assert_equal :multirdp_icon_too_big, result.error
  end

  def test_rejects_non_png
    result = MultirdpLicenses::IconValidator.check_bytes('GIF89a....')
    assert_not result.ok?
    assert_equal :multirdp_icon_not_png, result.error
  end

  def test_rejects_too_many_bytes
    png = build_png(8, 8)
    padded = png + ('x' * (256 * 1024))
    result = MultirdpLicenses::IconValidator.check_bytes(padded)
    assert_not result.ok?
    assert_equal :multirdp_icon_too_large, result.error
  end

  def test_rejects_bad_base64
    result = MultirdpLicenses::IconValidator.check_base64('not base64!!')
    assert_not result.ok?
    assert_equal :multirdp_icon_bad_base64, result.error
  end
end
