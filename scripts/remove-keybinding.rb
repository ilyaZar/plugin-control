#!/usr/bin/env ruby

require "tempfile"

path, plugin_id = ARGV
abort "usage: remove-keybinding.rb <bindings-file> <plugin-id>" unless path && plugin_id
exit 0 unless File.exist?(path) || File.symlink?(path)

target = File.realpath(path)
abort "bindings path is not a regular file" unless File.file?(target)

lines = File.binread(target).lines
output = []
removed = false
index = 0

while index < lines.length
  unless lines[index].match?(/^\s*(?:o|hl)\.bind\s*\(/)
    output << lines[index]
    index += 1
    next
  end

  block = []
  depth = 0
  begin
    line = lines[index]
    block << line
    depth += line.count("(") - line.count(")")
    index += 1
  end while index < lines.length && depth.positive?

  if block.join.include?(plugin_id)
    removed = true
    output.pop while output.last&.match?(/^\s*$/) && lines[index]&.match?(/^\s*$/)
  else
    output.concat(block)
  end
end

exit 0 unless removed

mode = File.stat(target).mode & 0o777
directory = File.dirname(target)
Tempfile.create([".bindings.lua.", ".tmp"], directory) do |file|
  file.binmode
  file.write(output.join)
  file.flush
  file.fsync
  File.chmod(mode, file.path)
  File.rename(file.path, target)
end
