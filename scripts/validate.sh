#!/usr/bin/env bash
# Check that the Claude marketplace manifest has the fields it needs, that
# every folder under skills/ is a well-formed skill, and that the manifest and
# the folders list the same skills.
#
# Usage: scripts/validate.sh [repository]
#
# With no argument it checks the repository this script is in. Give a folder to
# check that one instead, which is how scripts/test-validate.sh runs it against
# broken examples.
#
# The checks are written in Ruby, because SKILL.md frontmatter is YAML and
# needs a real YAML parser. macOS and the GitHub Actions ubuntu-latest runner
# both come with ruby and its built-in YAML and JSON libraries, so there is
# nothing to install.
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo "usage: $0 [repository]" >&2
  exit 2
fi

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"

if [ ! -d "$root" ]; then
  echo "error: $root is not a folder" >&2
  exit 2
fi

if ! command -v ruby >/dev/null 2>&1; then
  echo "error: validate.sh needs ruby to read SKILL.md frontmatter, and there is no ruby on the PATH." >&2
  echo "       macOS and the GitHub Actions ubuntu-latest runner both come with one (/usr/bin/ruby)." >&2
  exit 2
fi

exec ruby - "$root" <<'RUBY'
# encoding: utf-8
begin
  require "yaml"
  require "json"
rescue LoadError => e
  warn "error: validate.sh found ruby (#{RUBY_VERSION}), but it is missing a library that normally comes with it: #{e.message}"
  exit 2
end

ROOT = ARGV.fetch(0)
MANIFEST = ".claude-plugin/marketplace.json"

# The Claude apps reject an uploaded skill whose frontmatter has any top-level
# key outside these six, so scripts/package.sh makes no upload zip for one.
UPLOADABLE_KEYS = %w[name description license compatibility metadata allowed-tools].freeze

# Limits from the Agent Skills specification (agentskills.io/specification).
MAX_NAME = 64
MAX_DESCRIPTION = 1024

$errors = 0

def err(message)
  warn "error: #{message}"
  $errors += 1
end

def note(message)
  puts "note: #{message}"
end

# A JSON value's type, in plain words.
def kind(value)
  case value
  when nil then "null"
  when String then "text"
  when Numeric then "a number (#{value})"
  when true, false then "#{value}"
  when Array then "a list"
  when Hash then "an object"
  else value.class.to_s
  end
end

# Report a JSON field that is missing, not text, or empty. `where` says which
# object the field is in.
def check_text(object, key, where)
  if !object.key?(key)
    err %(#{where} has no "#{key}")
  elsif !object[key].is_a?(String)
    err %(#{where}: "#{key}" must be text, but it is #{kind(object[key])})
  elsif object[key].strip.empty?
    err %(#{where}: "#{key}" is empty)
  end
end

# --- The marketplace manifest -----------------------------------------------

# Returns the skill folders the manifest lists (such as "skills/issue-flow"),
# or nil when the manifest can't be read well enough to know.
def check_manifest
  path = File.join(ROOT, MANIFEST)
  unless File.file?(path)
    err "#{MANIFEST} was not found"
    return nil
  end

  begin
    manifest = JSON.parse(File.read(path, encoding: "UTF-8"))
  rescue JSON::ParserError, EncodingError => e
    err "#{MANIFEST} is not valid JSON (#{e.message.lines.first.to_s.strip.sub(/\A\d+: /, "")[0, 120]})"
    return nil
  end

  unless manifest.is_a?(Hash)
    err "#{MANIFEST} must be a JSON object, but it is #{kind(manifest)}"
    return nil
  end

  check_text(manifest, "name", MANIFEST)

  if !manifest.key?("owner")
    err %(#{MANIFEST} has no "owner")
  elsif !manifest["owner"].is_a?(Hash)
    err %(#{MANIFEST}: "owner" must be an object with a "name", but it is #{kind(manifest["owner"])})
  else
    check_text(manifest["owner"], "name", %(#{MANIFEST}: "owner"))
  end

  if !manifest.key?("plugins")
    err %(#{MANIFEST} has no "plugins" list)
    return nil
  elsif !manifest["plugins"].is_a?(Array)
    err %(#{MANIFEST}: "plugins" must be a list, but it is #{kind(manifest["plugins"])})
    return nil
  end

  listed = []
  manifest["plugins"].each_with_index do |plugin, index|
    where = "#{MANIFEST}: plugin #{index + 1}"
    unless plugin.is_a?(Hash)
      err "#{where} must be an object, but it is #{kind(plugin)}"
      next
    end
    where += %( ("#{plugin["name"]}")) if plugin["name"].is_a?(String) && !plugin["name"].strip.empty?

    check_text(plugin, "name", where)
    check_source(plugin, where)
    listed.concat(listed_skills(plugin, where))
  end
  listed.uniq
end

# A plugin's "source" is either a path inside this repository, as text, or an
# object that says where to fetch the plugin from. The object names its kind in
# a "source" key of its own, for example { "source": "github", "repo": "..." }.
def check_source(plugin, where)
  source = plugin["source"]
  if !plugin.key?("source")
    err %(#{where} has no "source")
  elsif source.is_a?(String)
    err %(#{where}: "source" is empty) if source.strip.empty?
  elsif source.is_a?(Hash)
    unless source["source"].is_a?(String) && !source["source"].strip.empty?
      err %(#{where}: its "source" object must name its kind in a "source" key of its own, for example "github")
    end
  else
    err %(#{where}: "source" must be a path such as "./", or an object saying where to fetch the plugin from, but it is #{kind(source)})
  end
end

def listed_skills(plugin, where)
  return [] unless plugin.key?("skills")
  skills = plugin["skills"]
  skills = [skills] if skills.is_a?(String)
  unless skills.is_a?(Array) && skills.all? { |skill| skill.is_a?(String) }
    err %(#{where}: "skills" must be a list of paths such as "./skills/my-skill")
    return []
  end
  skills.map { |skill| skill.sub(%r{\A\./}, "").sub(%r{/+\z}, "") }
end

# --- SKILL.md frontmatter ---------------------------------------------------

# The text of a `name` or `description` value, or nil if the value is not text
# (a list or nested keys). An empty value comes back as "".
def text_of(node)
  return nil unless node.is_a?(Psych::Nodes::Scalar)
  return "" if node.plain && ["", "~", "null", "Null", "NULL"].include?(node.value)
  node.value
end

# Returns the frontmatter's top-level keys and their value nodes, or nil after
# reporting why the frontmatter can't be read.
def read_frontmatter(file)
  text = File.binread(File.join(ROOT, file)).force_encoding("UTF-8")
  unless text.valid_encoding?
    err "#{file} is not UTF-8 text"
    return nil
  end

  # The frontmatter is the block between the first two '---' lines.
  lines = text.lines.map { |line| line.chomp.sub(/[ \t\r]+\z/, "") }
  unless lines.first == "---"
    err "#{file} has no frontmatter: its first line must be ---"
    return nil
  end
  close = lines[1..-1].index("---")
  if close.nil?
    err "#{file}: the frontmatter is never closed. It opens with --- on line 1, but no later line is ---"
    return nil
  end

  begin
    documents = Psych.parse_stream(lines[1, close].join("\n") + "\n").children
  rescue Psych::SyntaxError => e
    # Psych counts lines from the one after the opening ---, starting at 1.
    problem = [e.problem, e.context].compact.join(" ")
    err "#{file}: the frontmatter is not valid YAML (line #{e.line + 1}: #{problem})"
    return nil
  end

  if documents.empty? || documents.first.root.nil?
    err "#{file}: the frontmatter is empty"
    return nil
  end
  root = documents.first.root
  unless documents.length == 1 && root.is_a?(Psych::Nodes::Mapping)
    err "#{file}: the frontmatter must be 'key: value' lines, such as 'name: my-skill'"
    return nil
  end

  fields = {}
  root.children.each_slice(2) do |key, value|
    unless key.is_a?(Psych::Nodes::Scalar)
      err "#{file}: the frontmatter has a key that is not plain text"
      return nil
    end
    if fields.key?(key.value)
      err %(#{file}: the frontmatter has "#{key.value}" more than once)
      return nil
    end
    fields[key.value] = value
  end
  fields
end

# What is wrong with a skill name under the Agent Skills naming rules, as a
# list of reasons. The rules allow lowercase letters, digits and hyphens.
def name_problems(name)
  problems = []
  problems << "it is #{name.length} characters and the limit is #{MAX_NAME}" if name.length > MAX_NAME
  unless name.match?(/\A[\p{L}\p{N}-]+\z/) && name == name.downcase
    problems << "it may only contain lowercase letters, digits and hyphens"
  end
  problems << "it must not start or end with a hyphen" if name.start_with?("-") || name.end_with?("-")
  problems << "it must not have two hyphens in a row" if name.include?("--")
  problems
end

def check_skill(folder)
  file = "skills/#{folder}/SKILL.md"
  fields = read_frontmatter(file)
  return if fields.nil?

  if !fields.key?("name")
    err "#{file} has no name in its frontmatter"
  else
    name = text_of(fields["name"])
    if name.nil?
      err "#{file}: name must be text, not a list or nested keys"
    elsif name.strip.empty?
      err "#{file}: name is empty"
    else
      err %(#{file}: name "#{name}" does not match its folder name "#{folder}") if name != folder
      problems = name_problems(name)
      unless problems.empty?
        err %(#{file}: name "#{name}" breaks the Agent Skills naming rules: #{problems.join("; ")})
      end
    end
  end

  if !fields.key?("description")
    err "#{file} has no description in its frontmatter"
  else
    description = text_of(fields["description"])
    if description.nil?
      err "#{file}: description must be text, not a list or nested keys"
    elsif description.strip.empty?
      err "#{file}: description is empty"
    elsif description.strip.length > MAX_DESCRIPTION
      err "#{file}: description is #{description.strip.length} characters and the limit is #{MAX_DESCRIPTION}"
    end
  end

  other = fields.keys - UPLOADABLE_KEYS
  unless other.empty?
    note "skills/#{folder} gets no upload zip, because the Claude apps reject these frontmatter keys: #{other.join(", ")}"
  end
end

# --- Run the checks ---------------------------------------------------------

begin
  listed = check_manifest

  skills_dir = File.join(ROOT, "skills")
  folders = []
  if File.directory?(skills_dir)
    folders = Dir.children(skills_dir).sort.select do |entry|
      !entry.start_with?(".") && File.directory?(File.join(skills_dir, entry))
    end
  end

  on_disk = []
  without_skill_md = []
  folders.each do |folder|
    # Look the file up by its exact name: macOS would otherwise accept
    # skill.md, which Linux does not.
    if Dir.children(File.join(skills_dir, folder)).include?("SKILL.md")
      on_disk << "skills/#{folder}"
      check_skill(folder)
    else
      without_skill_md << "skills/#{folder}"
      err "skills/#{folder} has no SKILL.md"
    end
  end

  err "no skills found under skills/" if on_disk.empty? && without_skill_md.empty?

  unless listed.nil?
    (on_disk - listed).each { |skill| err "#{skill} is not listed in #{MANIFEST}" }
    (listed - on_disk - without_skill_md).each do |skill|
      err "#{MANIFEST} lists #{skill}, which has no SKILL.md"
    end
  end
rescue SystemCallError => e
  err "could not read the repository: #{e.message}"
end

if $errors > 0
  warn "validation failed: #{$errors} problem(s)"
  exit 1
end
puts "ok: #{on_disk.length} skill(s), manifest in sync"
RUBY
