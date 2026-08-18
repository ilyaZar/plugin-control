#!/usr/bin/env ruby

require "tempfile"
require_relative "../lib/channel_config"

DEFAULT = File.expand_path("../config/channels.yaml", __dir__)

def parse(text)
  Tempfile.create(["channels", ".yaml"]) do |file|
    file.write(text)
    file.flush
    return PluginControl.load_file(file.path)
  end
end

def assert(value, message = "assertion failed")
  raise message unless value
end

def assert_equal(expected, actual)
  raise "expected #{expected.inspect}, got #{actual.inspect}" unless expected == actual
end

def invalid_error(text)
  begin
    parse(text)
  rescue StandardError => error
    return error
  end
  raise "expected invalid configuration"
end

def assert_invalid(text, message = nil)
  error = invalid_error(text)
  if message
    assert(error.message.include?(message),
      "expected error to include #{message.inspect}, got #{error.message.inspect}")
  end
  error
end

def assert_diagnostic(text, field, expected, recoverable = true)
  error = invalid_error(text)
  assert_equal field, error.field
  assert(error.expected.include?(expected),
    "expected #{error.expected.inspect} to include #{expected.inspect}")
  assert_equal recoverable, error.recoverable
  error
end

def test(name)
  yield
  puts "ok - #{name}"
rescue StandardError => error
  warn "not ok - #{name}"
  warn error.full_message
  exit 1
end

def default_text
  File.read(DEFAULT)
end

test("valid default config") do
  config = PluginControl.load_file(DEFAULT)
  assert_equal 2, config["version"]
  assert_equal 30, config["refresh_minutes"]
  assert_equal false, config.dig("settings", "tray-icon-hidden")
end

test("settings mapping is required") do
  without_settings = default_text.sub(/\nsettings:\n.*?\nchannels:/m,
    "\nchannels:")
  assert_invalid(without_settings,
    "settings must be a mapping")
end

test("every settings field is required") do
  assert_invalid(default_text.sub("settings:\n  tray-icon-hidden: false",
    "settings: {}"),
    "settings.tray-icon-hidden must be true or false")
end

test("tray icon can default to hidden") do
  config = parse(default_text.sub("tray-icon-hidden: false",
    "tray-icon-hidden: true"))
  assert_equal true, config.dig("settings", "tray-icon-hidden")
end

test("invalid tray icon setting fails") do
  error = assert_diagnostic(default_text.sub("tray-icon-hidden: false",
    "tray-icon-hidden: hidden"), "settings.tray-icon-hidden",
    "true or false")
  assert_equal '"hidden"', error.actual
end

test("unknown settings fail") do
  assert_invalid(default_text.sub("  tray-icon-hidden: false",
    "  tray-icon-hidden: false\n  command: rm -rf"), "unknown")
end

test("unlisted channel disabled by default") do
  channel = PluginControl.load_file(DEFAULT)["channels"].find do |item|
    item["id"] == "hancore-submissions"
  end
  assert(!channel["enabled"])
end

test("browse can be enabled without install permission") do
  config = parse(default_text.sub("enabled: false", "enabled: true"))
  assert(config["channels"][1]["enabled"])
  assert(!config["allow_unlisted_installs"])
end

test("install permission can be enabled") do
  config = parse(default_text.sub("allow_unlisted_installs: false",
    "allow_unlisted_installs: true"))
  assert(config["allow_unlisted_installs"])
end

test("unknown schema version fails") do
  assert_invalid(default_text.sub("version: 2", "version: 1"), "unsupported")
end

test("duplicate channel IDs fail") do
  assert_invalid(default_text.sub("id: hancore-submissions", "id: marketplace"),
    "duplicate")
end

test("unsafe YAML tags fail") do
  assert_invalid("--- !ruby/object:Object {}\n", "unspecified class")
end

test("YAML aliases fail") do
  assert_invalid("version: 2\nrefresh_minutes: 30\nchannels: &x []\ncopy: *x\n",
    "Alias parsing was not enabled")
end

test("non-HTTPS URLs fail") do
  assert_invalid(default_text.sub("https://omarchyplugins.com/catalog.json",
    "http://omarchyplugins.com/catalog.json"), "HTTPS")
end

test("embedded credentials fail") do
  error = assert_invalid(default_text.sub(
    "https://omarchyplugins.com/catalog.json",
    "https://user:pass@omarchyplugins.com/catalog.json"), "credentials")
  assert_equal '"https://omarchyplugins.com/catalog.json"', error.actual
  assert(!error.actual.include?("user"))
  assert(!error.actual.include?("pass"))
end

test("URL diagnostics redact query values and fragments") do
  error = assert_invalid(default_text.sub(
    "https://omarchyplugins.com/catalog.json",
    '"https://omarchyplugins.com/catalog.json?token=secret#bad"'), "fragment")
  assert_equal '"https://omarchyplugins.com/catalog.json"', error.actual
  assert(!error.actual.include?("secret"))
end

test("invalid GitHub repository names fail") do
  assert_invalid(default_text.sub("HANCORE-linux/omarchy-plugin-marketplace",
    "HANCORE-linux/not valid"), "owner/repository")
end

test("arbitrary command fields fail") do
  assert_invalid(default_text.sub("    catalog_url:",
    "    install_command: curl bad | bash\n    catalog_url:"), "unknown")
end

test("every schema field reports an admissible value") do
  cases = [
    [default_text.sub("version: 2", "version: current"),
      "version", "integer 2", false],
    [default_text.sub("refresh_minutes: 30", "refresh_minutes: fast"),
      "refresh_minutes", "integer from 5 through 1440", true],
    [default_text.sub("allow_unlisted_installs: false",
      "allow_unlisted_installs: sometimes"),
      "allow_unlisted_installs", "true or false", true],
    [default_text.sub("  - id: marketplace", "  - id: Marketplace"),
      "channels[0].id", "lowercase letters", true],
    [default_text.sub("    name: Omarchy Plugins Marketplace",
      "    name: 42"), "channels[0].name", "a string", true],
    [default_text.sub("    type: marketplace-catalog",
      "    type: other"), "channels[0].type",
      "marketplace-catalog or github-submissions", true],
    [default_text.sub("    enabled: true", "    enabled: hidden"),
      "channels[0].enabled", "true or false", true],
    [default_text.sub("https://omarchyplugins.com/catalog.json",
      "http://omarchyplugins.com/catalog.json"),
      "channels[0].catalog_url", "HTTPS URL", true],
    [default_text.sub("website_url: https://omarchyplugins.com/",
      "website_url: http://omarchyplugins.com/"),
      "channels[0].website_url", "HTTPS URL", true],
    [default_text.sub("HANCORE-linux/omarchy-plugin-marketplace",
      "not a repository"), "channels[1].repository",
      "owner/repository", true],
    [default_text.sub("    required_labels:\n      - submission\n      - validated",
      "    required_labels: submission"),
      "channels[1].required_labels", "array of strings", true],
    [default_text.sub("    excluded_labels:\n      - listed\n      - needs-fixes",
      "    excluded_labels: listed"),
      "channels[1].excluded_labels", "array of strings", true]
  ]
  cases.each do |text, field, expected, recoverable|
    assert_diagnostic(text, field, expected, recoverable)
  end
end
