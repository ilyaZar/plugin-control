#!/usr/bin/env ruby

require "json"
require "psych"
require "uri"

module PluginControl
  class ConfigError < StandardError
    attr_reader :field, :actual, :expected, :recoverable

    def initialize(message, field: nil, actual: nil, expected: nil,
      recoverable: true)
      super(message)
      @field = field
      @actual = actual
      @expected = expected
      @recoverable = recoverable
    end
  end

  TOP_KEYS = %w[
    version refresh_minutes allow_unlisted_installs settings channels
  ].freeze
  SETTINGS_KEYS = %w[tray-icon-hidden background_dim].freeze
  CHANNEL_KEYS = %w[
    id name type enabled catalog_url website_url repository required_labels
    excluded_labels
  ].freeze
  CHANNEL_TYPES = %w[marketplace-catalog github-submissions].freeze

  module_function

  def describe_value(value)
    rendered = if value.is_a?(String) &&
        value.match?(%r{\A[a-z][a-z0-9+.-]*://[^/\s]*@}i)
      '"[redacted URL]"'
    else
      value.inspect
    end
    rendered.length > 120 ? "#{rendered[0, 117]}..." : rendered
  end

  def describe_url(value)
    return describe_value(value) unless value.is_a?(String)

    uri = URI.parse(value)
    return '"[redacted invalid URL]"' if uri.host.to_s.empty?

    sanitized = uri.dup
    sanitized.user = nil
    sanitized.password = nil
    sanitized.query = nil
    sanitized.fragment = nil
    describe_value(sanitized.to_s)
  rescue URI::InvalidURIError
    '"[redacted invalid URL]"'
  end

  def fail_config(message, field: nil, actual: nil, expected: nil,
    recoverable: true, redact_url: false)
    rendered_actual = if actual.nil?
      nil
    elsif redact_url
      describe_url(actual)
    else
      describe_value(actual)
    end
    raise ConfigError.new(message, field: field,
      actual: rendered_actual,
      expected: expected, recoverable: recoverable)
  end

  def exact_boolean(value, field)
    unless [true, false].include?(value)
      fail_config("#{field} must be true or false", field: field,
        actual: value, expected: "true or false")
    end
    value
  end

  def required_string(value, field, maximum = 200, redact_url: false)
    unless value.is_a?(String)
      fail_config("#{field} must be a string", field: field,
        actual: value, expected: "a string", redact_url: redact_url)
    end
    value = value.strip
    if value.empty?
      fail_config("#{field} must not be empty", field: field,
        actual: value, expected: "a non-empty string", redact_url: redact_url)
    end
    if value.length > maximum
      fail_config("#{field} is too long", field: field, actual: value,
        expected: "a string of at most #{maximum} characters",
        redact_url: redact_url)
    end
    if value.match?(/[[:cntrl:]]/)
      fail_config("#{field} contains control characters", field: field,
        actual: value, expected: "a string without control characters",
        redact_url: redact_url)
    end
    value
  end

  def https_url(value, field)
    raw = required_string(value, field, 2_048, redact_url: true)
    uri = URI.parse(raw)
    unless uri.is_a?(URI::HTTPS)
      fail_config("#{field} must use HTTPS", field: field, actual: raw,
        expected: "an HTTPS URL", redact_url: true)
    end
    if uri.host.to_s.empty?
      fail_config("#{field} must include a host", field: field, actual: raw,
        expected: "an HTTPS URL with a host", redact_url: true)
    end
    if uri.userinfo
      fail_config("#{field} must not include credentials", field: field,
        actual: raw, expected: "an HTTPS URL without credentials",
        redact_url: true)
    end
    if uri.fragment
      fail_config("#{field} must not include a fragment", field: field,
        actual: raw, expected: "an HTTPS URL without a fragment",
        redact_url: true)
    end
    raw
  rescue URI::InvalidURIError
    fail_config("#{field} is not a valid URL", field: field, actual: value,
      expected: "a valid HTTPS URL", redact_url: true)
  end

  def string_list(value, field)
    unless value.is_a?(Array)
      fail_config("#{field} must be an array", field: field, actual: value,
        expected: "an array of strings")
    end
    if value.length > 20
      fail_config("#{field} has too many values", field: field,
        actual: value, expected: "an array of at most 20 strings")
    end
    value.map.with_index do |entry, index|
      required_string(entry, "#{field}[#{index}]", 80)
    end.uniq
  end

  def validate_channel(value, index)
    field = "channels[#{index}]"
    unless value.is_a?(Hash)
      fail_config("#{field} must be a mapping", field: field, actual: value,
        expected: "a channel mapping")
    end
    unknown = value.keys.map(&:to_s) - CHANNEL_KEYS
    unless unknown.empty?
      fail_config("#{field} has unknown fields: #{unknown.join(', ')}",
        field: field, actual: unknown,
        expected: "only #{CHANNEL_KEYS.join(', ')}")
    end

    channel = value.transform_keys(&:to_s)
    id_field = "#{field}.id"
    id = required_string(channel["id"], id_field, 80)
    unless id.match?(/\A[a-z0-9][a-z0-9._-]*\z/)
      fail_config("#{id_field} is invalid", field: id_field, actual: id,
        expected: "lowercase letters, digits, dots, underscores, or hyphens")
    end
    type_field = "#{field}.type"
    type = required_string(channel["type"], type_field, 80)
    unless CHANNEL_TYPES.include?(type)
      fail_config("#{type_field} is unsupported", field: type_field,
        actual: type, expected: CHANNEL_TYPES.join(" or "))
    end

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
      unless valid_repository
        fail_config("channels[#{index}].repository must be owner/repository",
          field: "channels[#{index}].repository", actual: repository,
          expected: "owner/repository")
      end
      out["repository"] = repository
      out["required_labels"] = string_list(channel.fetch("required_labels", []), "channels[#{index}].required_labels")
      out["excluded_labels"] = string_list(channel.fetch("excluded_labels", []), "channels[#{index}].excluded_labels")
    end
    out
  end

  def validate_settings(value)
    unless value.is_a?(Hash)
      fail_config("settings must be a mapping", field: "settings",
        actual: value, expected: "a settings mapping")
    end
    unknown = value.keys.map(&:to_s) - SETTINGS_KEYS
    unless unknown.empty?
      fail_config("settings has unknown fields: #{unknown.join(', ')}",
        field: "settings", actual: unknown,
        expected: "only #{SETTINGS_KEYS.join(', ')}")
    end

    settings = value.transform_keys(&:to_s)
    {
      "tray-icon-hidden" => exact_boolean(
        settings["tray-icon-hidden"],
        "settings.tray-icon-hidden"),
      "background_dim" => exact_boolean(
        settings["background_dim"],
        "settings.background_dim")
    }
  end

  def validate(value)
    unless value.is_a?(Hash)
      fail_config("configuration must be a mapping", field: "configuration",
        actual: value, expected: "a YAML mapping")
    end
    config = value.transform_keys(&:to_s)
    unknown = config.keys - TOP_KEYS
    unless unknown.empty?
      fail_config("unknown configuration fields: #{unknown.join(', ')}",
        field: "configuration", actual: unknown,
        expected: "only #{TOP_KEYS.join(', ')}")
    end
    unless config["version"] == 2
      fail_config("unsupported configuration version", field: "version",
        actual: config["version"], expected: "the integer 2",
        recoverable: false)
    end

    refresh = config.fetch("refresh_minutes", 30)
    valid_refresh = refresh.is_a?(Integer) && refresh.between?(5, 1_440)
    unless valid_refresh
      fail_config("refresh_minutes must be an integer from 5 through 1440",
        field: "refresh_minutes", actual: refresh,
        expected: "an integer from 5 through 1440")
    end
    out = {
      "version" => 2,
      "refresh_minutes" => refresh,
      "allow_unlisted_installs" => exact_boolean(
        config.fetch("allow_unlisted_installs", false),
        "allow_unlisted_installs"),
      "settings" => validate_settings(config["settings"])
    }
    channels = config["channels"]
    unless channels.is_a?(Array) && !channels.empty?
      fail_config("channels must be a non-empty array", field: "channels",
        actual: channels, expected: "a non-empty array of channel mappings")
    end
    if channels.length > 20
      fail_config("channels has too many entries", field: "channels",
        actual: channels.length, expected: "at most 20 channel mappings")
    end
    out["channels"] = channels.map.with_index do |channel, index|
      validate_channel(channel, index)
    end
    ids = out["channels"].map { |channel| channel["id"] }
    unless ids.uniq.length == ids.length
      fail_config("duplicate channel IDs are not allowed", field: "channels",
        actual: ids, expected: "unique channel IDs")
    end
    out
  end

  def load_file(path)
    raw = File.binread(path, 131_073)
    if raw.bytesize > 131_072
      fail_config("configuration is larger than 128 KiB",
        field: "configuration", actual: "#{raw.bytesize} bytes",
        expected: "at most 128 KiB", recoverable: false)
    end
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
      error: "unsafe or malformed YAML: #{error.message}", line: line,
      field: "configuration",
      expected: "valid YAML without aliases or custom tags",
      recoverable: false)
    exit 1
  rescue PluginControl::ConfigError => error
    puts JSON.generate(ok: false, error: error.message, line: nil,
      field: error.field, actual: error.actual, expected: error.expected,
      recoverable: error.recoverable)
    exit 1
  rescue Errno::ENOENT, Errno::EACCES, IndexError => error
    puts JSON.generate(ok: false, error: error.message, line: nil,
      field: "configuration", expected: "a readable YAML file",
      recoverable: false)
    exit 1
  end
end
