#!/usr/bin/env ruby

require "json"
require "psych"
require "uri"

module PluginControl
  class ConfigError < StandardError; end

  TOP_KEYS = %w[
    version refresh_minutes allow_unlisted_installs settings channels
  ].freeze
  SETTINGS_KEYS = %w[tray-icon-hidden].freeze
  CHANNEL_KEYS = %w[
    id name type enabled catalog_url website_url repository required_labels
    excluded_labels
  ].freeze
  CHANNEL_TYPES = %w[marketplace-catalog github-submissions].freeze

  module_function

  def fail_config(message)
    raise ConfigError, message
  end

  def exact_boolean(value, field)
    fail_config("#{field} must be true or false") unless [true, false].include?(value)
    value
  end

  def required_string(value, field, maximum = 200)
    fail_config("#{field} must be a string") unless value.is_a?(String)
    value = value.strip
    fail_config("#{field} must not be empty") if value.empty?
    fail_config("#{field} is too long") if value.length > maximum
    fail_config("#{field} contains control characters") if value.match?(/[[:cntrl:]]/)
    value
  end

  def https_url(value, field)
    raw = required_string(value, field, 2_048)
    uri = URI.parse(raw)
    fail_config("#{field} must use HTTPS") unless uri.is_a?(URI::HTTPS)
    fail_config("#{field} must include a host") if uri.host.to_s.empty?
    fail_config("#{field} must not include credentials") if uri.userinfo
    fail_config("#{field} must not include a fragment") if uri.fragment
    raw
  rescue URI::InvalidURIError
    fail_config("#{field} is not a valid URL")
  end

  def string_list(value, field)
    fail_config("#{field} must be an array") unless value.is_a?(Array)
    fail_config("#{field} has too many values") if value.length > 20
    value.map.with_index do |entry, index|
      required_string(entry, "#{field}[#{index}]", 80)
    end.uniq
  end

  def validate_channel(value, index)
    fail_config("channels[#{index}] must be a mapping") unless value.is_a?(Hash)
    unknown = value.keys.map(&:to_s) - CHANNEL_KEYS
    fail_config("channels[#{index}] has unknown fields: #{unknown.join(', ')}") unless unknown.empty?

    channel = value.transform_keys(&:to_s)
    id = required_string(channel["id"], "channels[#{index}].id", 80)
    fail_config("channels[#{index}].id is invalid") unless id.match?(/\A[a-z0-9][a-z0-9._-]*\z/)
    type = required_string(channel["type"], "channels[#{index}].type", 80)
    fail_config("channels[#{index}].type is unsupported") unless CHANNEL_TYPES.include?(type)

    out = {
      "id" => id,
      "name" => required_string(channel["name"], "channels[#{index}].name", 120),
      "type" => type,
      "enabled" => exact_boolean(channel.fetch("enabled", true), "channels[#{index}].enabled")
    }

    if type == "marketplace-catalog"
      out["catalog_url"] = https_url(channel["catalog_url"], "channels[#{index}].catalog_url")
      if channel.key?("website_url")
        out["website_url"] = https_url(channel["website_url"],
          "channels[#{index}].website_url")
      end
    else
      repository = required_string(channel["repository"], "channels[#{index}].repository", 160)
      valid_repository = repository.match?(
        /\A[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})\/[A-Za-z0-9._-]{1,100}\z/
      )
      fail_config("channels[#{index}].repository must be owner/repository") \
        unless valid_repository
      out["repository"] = repository
      out["required_labels"] = string_list(channel.fetch("required_labels", []), "channels[#{index}].required_labels")
      out["excluded_labels"] = string_list(channel.fetch("excluded_labels", []), "channels[#{index}].excluded_labels")
    end
    out
  end

  def validate_settings(value)
    fail_config("settings must be a mapping") unless value.is_a?(Hash)
    unknown = value.keys.map(&:to_s) - SETTINGS_KEYS
    fail_config("settings has unknown fields: #{unknown.join(', ')}") unless unknown.empty?

    settings = value.transform_keys(&:to_s)
    {
      "tray-icon-hidden" => exact_boolean(
        settings["tray-icon-hidden"],
        "settings.tray-icon-hidden")
    }
  end

  def validate(value)
    fail_config("configuration must be a mapping") unless value.is_a?(Hash)
    config = value.transform_keys(&:to_s)
    unknown = config.keys - TOP_KEYS
    fail_config("unknown configuration fields: #{unknown.join(', ')}") unless unknown.empty?
    fail_config("unsupported configuration version") unless config["version"] == 2

    refresh = config.fetch("refresh_minutes", 30)
    valid_refresh = refresh.is_a?(Integer) && refresh.between?(5, 1_440)
    fail_config("refresh_minutes must be an integer from 5 through 1440") \
      unless valid_refresh
    out = {
      "version" => 2,
      "refresh_minutes" => refresh,
      "allow_unlisted_installs" => exact_boolean(
        config.fetch("allow_unlisted_installs", false),
        "allow_unlisted_installs"),
      "settings" => validate_settings(config["settings"])
    }
    channels = config["channels"]
    fail_config("channels must be a non-empty array") unless channels.is_a?(Array) && !channels.empty?
    fail_config("channels has too many entries") if channels.length > 20
    out["channels"] = channels.map.with_index do |channel, index|
      validate_channel(channel, index)
    end
    ids = out["channels"].map { |channel| channel["id"] }
    fail_config("duplicate channel IDs are not allowed") unless ids.uniq.length == ids.length
    out
  end

  def load_file(path)
    raw = File.binread(path, 131_073)
    fail_config("configuration is larger than 128 KiB") if raw.bytesize > 131_072
    parsed = Psych.safe_load(raw, permitted_classes: [], permitted_symbols: [], aliases: false)
    validate(parsed)
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    path = ARGV.fetch(0)
    puts JSON.generate(ok: true, config: PluginControl.load_file(path))
  rescue Psych::Exception => error
    line = error.respond_to?(:line) ? error.line : nil
    puts JSON.generate(ok: false,
      error: "unsafe or malformed YAML: #{error.message}", line: line)
    exit 1
  rescue PluginControl::ConfigError, Errno::ENOENT, Errno::EACCES,
         IndexError => error
    puts JSON.generate(ok: false, error: error.message, line: nil)
    exit 1
  end
end
