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

def assert_invalid(text, message = nil)
  begin
    parse(text)
  rescue StandardError => error
    assert(error.message.include?(message),
      "expected error to include #{message.inspect}, got #{error.message.inspect}") if message
    return
  end
  raise "expected invalid configuration"
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
  assert_equal 1, config["version"]
  assert_equal 30, config["refresh_minutes"]
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
  assert_invalid(default_text.sub("version: 1", "version: 2"), "unsupported")
end

test("duplicate channel IDs fail") do
  assert_invalid(default_text.sub("id: hancore-submissions", "id: marketplace"),
    "duplicate")
end

test("unsafe YAML tags fail") do
  assert_invalid("--- !ruby/object:Object {}\n", "unspecified class")
end

test("YAML aliases fail") do
  assert_invalid("version: 1\nrefresh_minutes: 30\nchannels: &x []\ncopy: *x\n",
    "Alias parsing was not enabled")
end

test("non-HTTPS URLs fail") do
  assert_invalid(default_text.sub("https://omarchyplugins.com/catalog.json",
    "http://omarchyplugins.com/catalog.json"), "HTTPS")
end

test("embedded credentials fail") do
  assert_invalid(default_text.sub("https://omarchyplugins.com/catalog.json",
    "https://user:pass@omarchyplugins.com/catalog.json"), "credentials")
end

test("invalid GitHub repository names fail") do
  assert_invalid(default_text.sub("HANCORE-linux/omarchy-plugin-marketplace",
    "HANCORE-linux/not valid"), "owner/repository")
end

test("arbitrary command fields fail") do
  assert_invalid(default_text.sub("    catalog_url:",
    "    install_command: curl bad | bash\n    catalog_url:"), "unknown")
end
