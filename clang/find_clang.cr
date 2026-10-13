#!/usr/bin/env crystal run

# This is a helper script. It requires `llvm-config` to point to the
# LLVM version which is to be used.
# It calls llvm-config and clang binaries to retrieve their settings and
# parse them for further use.

# As part of the run, it generates some files.
# It outputs all LLVM and Clang libraries to link to.
# Provides diagnostics to standard error.
# This script is called automatically by CMake.
# Can be invoked manually. Invoke with --help for options.

require "option_parser"
require "yaml"
require "../src/bindgen/util"
require "../src/bindgen/find_path"

# Parse command line options. Each of these options has an accessor
# function of the same name, defined at the end of file.
OPTIONS = Hash(Symbol, Bool | String | Nil | Array(String)).new
OPTIONS[:clang] = nil
OPTIONS[:llvm_config] = nil
OPTIONS[:print_llvm_libs] = false
OPTIONS[:print_clang_libs] = false
OPTIONS[:quiet] = false
OPTIONS[:debug] = false
OPTIONS[:cppflags] = [] of String
OPTIONS[:ldflags] = [] of String
OPTIONS[:system_include_dirs] = [] of String
OPTIONS[:system_lib_dirs] = [] of String
OPTIONS[:system_libs] = [] of String
OPTIONS[:generated_hpp] = File.expand_path "#{__DIR__}/include/generated.hpp"
OPTIONS[:variables] = File.expand_path "#{__DIR__}/variables.yml"
OPTIONS[:spec_base] = File.expand_path "#{__DIR__}/../spec/integration/spec_base.yml"
parse_cli_args

# Link against LLVM's shared rather than static libraries?  Auto-detected below
# if unset.
dynamic = ENV["BINDGEN_DYNAMIC"]?.presence.try(&.==("1"))

# Determine which llvm-config we are using
unless OPTIONS[:llvm_config] ||= find_llvm_config_binary min_version: "14.0.0"
  log "Cant find llvm config"
  print_help_and_exit
end
log "Using llvm-config binary in #{OPTIONS[:llvm_config].inspect}."

# Extract basic data from llvm-config:

OPTIONS[:llvm_version] = output_of(OPTIONS[:llvm_config], "--version")

OPTIONS[:llvm_cxx_flags] = output_of(OPTIONS[:llvm_config], "--cxxflags")
  .gsub(/-fno-exceptions/, "")
  .gsub(/-W[^alp].+\s/, "")
  .gsub(/\s+/, " ")

OPTIONS[:llvm_ld_flags] = output_of(OPTIONS[:llvm_config], "--ldflags")
  .gsub(/\s+/, " ")

OPTIONS[:llvm_bindir] = output_of(OPTIONS[:llvm_config], "--bindir")
OPTIONS[:llvm_libdir] = output_of(OPTIONS[:llvm_config], "--libdir")

# Determine which clang++ we are using
unless OPTIONS[:clang] ||= find_clang_binary([llvm_bindir], min_version: "14.0.0")
  log "Cant find clang"
  print_help_and_exit
end
log "Using clang binary in #{OPTIONS[:clang].inspect}. Querying it."

# Ask clang the paths it uses. This output will then be parsed in detail.
output = log_and_run("#{clang} -### #{__DIR__}/src/bindgen.cpp 2>&1").lines
if output.size < 2 # Sanity check
  STDERR.puts %(Unexpected output from "#{clang}": Expected at least two lines.)
  exit 1
end
parse_clang_output output

# Now extract clang and llvm-specific libs.  Static libraries are preferred if
# both kinds are available, but the two kinds are never mixed.
static_clang_libs = find_static_libraries(system_lib_dirs, "clang")
static_llvm_libs = find_static_libraries(system_lib_dirs, "LLVM")
dynamic = static_clang_libs.empty? || static_llvm_libs.empty? if dynamic.nil?
log "Linking LLVM and Clang #{dynamic ? "dynamically" : "statically"}. (Adjust with env BINDGEN_DYNAMIC=0/1 if needed)"

if dynamic
  OPTIONS[:clang_libs] = find_shared_libraries(system_lib_dirs, "clang", "clang-cpp")
  OPTIONS[:llvm_libs] = find_shared_libraries(system_lib_dirs, "LLVM", "LLVM")
else
  OPTIONS[:clang_libs] = static_clang_libs
  OPTIONS[:llvm_libs] = static_llvm_libs
  # Static LLVM libraries don't pull in their own dependencies.
  OPTIONS[:system_libs] = output_of(llvm_config, "--system-libs", "--link-static").split
end
# See if only partial info was requested:

if OPTIONS[:debug]
  pp OPTIONS
  exit
end

if OPTIONS[:print_clang_libs]
  log "Option --print-clang-libs detected. Printing libraries and exiting."
  STDOUT << get_lib_args(clang_libs).join(";")
  exit
end

if OPTIONS[:print_llvm_libs]
  log "Option --print-llvm-libs detected. Printing libraries and exiting."
  STDOUT << (get_lib_args(llvm_libs) + system_libs).join(";")
  exit
end

# Provide user with help if we didn't find libraries in the output.
if llvm_libs.empty? || clang_libs.empty?
  log "Cannot find LLVM libs" if llvm_libs.empty?
  log "Cannot find Clang libs" if clang_libs.empty?
  print_help_and_exit
end

# If this is a full run (i.e. not asking for specific things), continue:

# Generate the output header file.  This will be accessed from the clang tool.
log "Generating #{generated_hpp}"
write_if_changed(generated_hpp, String.build do |b|
  b.puts generated_header("//")
  b.puts
  b.puts "#define BG_SYSTEM_INCLUDES { #{system_include_dirs.map(&.inspect).join(", ")} }"
end)

# Generate variables.yml file
log "Generating #{variables}"
variables_content = {
  clang:          clang,
  llvm_config:    llvm_config,
  llvm_version:   llvm_version,
  llvm_cxx_flags: llvm_cxx_flags,
  llvm_ld_flags:  llvm_ld_flags,
  includes:       system_include_dirs.map { |x| File.expand_path(x) },
  clang_libs:     get_lib_args(clang_libs),
  llvm_libs:      get_lib_args(llvm_libs) + system_libs,
}.to_yaml
write_if_changed(variables, "#{generated_header("#")}\n#{variables_content}")

# Generate spec_base.yml
log "Generating #{spec_base}"
spec_base_content = {
  module:     "Test",
  generators: {
    cpp: {
      output: "tmp/{SPEC_NAME}.cpp",
      build:  "#{clang} #{llvm_cxx_flags} #{system_include_dirs.map { |x| "-I#{File.expand_path(x)}" }.join(' ')}" \
             " -c -o {SPEC_NAME}.o {SPEC_NAME}.cpp -I.. -Wall -Werror -Wno-unused-function" \
             "#{dynamic ? "" : " -fPIC"}",
      preamble: <<-PREAMBLE
      #include <gc/gc_cpp.h>
      #include "bindgen_helper.hpp"
      PREAMBLE
    },
    crystal: {
      output: "tmp/{SPEC_NAME}.cr",
    },
  },
  library: "%/tmp/{SPEC_NAME}.o -lstdc++ -lgccpp",
  parser:  {
    files:    ["{SPEC_NAME}.cpp"],
    includes: [
      "%",
    ].concat(system_include_dirs),
  },
}.to_yaml
write_if_changed(spec_base, "#{generated_header("#")}\n#{spec_base_content}")

#################################################
# Helper functions found below.

# Parses the command line into `OPTIONS`.
def parse_cli_args
  # `crystal find_clang.cr -- --option` passes the `--` on.
  OptionParser.parse(ARGV.reject("--")) do |parser|
    parser.banner = "find_clang.cr [options]"

    parser.on("--llvm-config PATH", "Path to llvm-config binary (default: find llvm-config[-*] in PATH)") { |path| OPTIONS[:llvm_config] = path }
    parser.on("--clang PATH", "Path to clang binary (default: find clang++[-*] in llvm bindir)") { |path| OPTIONS[:clang] = path }
    parser.on("--print-clang-libs", "Print detected clang libs and exit") { OPTIONS[:print_clang_libs] = true }
    parser.on("--print-llvm-libs", "Print detected llvm libs and exit") { OPTIONS[:print_llvm_libs] = true }
    parser.on("--quiet", "Suppress diagnostic/debug STDERR output") { OPTIONS[:quiet] = true }
    parser.on("--debug", "Print the complete internal and parsed config and exit") { OPTIONS[:debug] = true }
    parser.on("--help", "This help") do
      STDERR.puts parser
      exit 1
    end

    parser.invalid_option do |flag|
      STDERR.puts "Unknown option #{flag}", parser
      exit 1
    end

    parser.missing_option do |flag|
      STDERR.puts "Option #{flag} expects a value", parser
      exit 1
    end
  end
end

# Finds clang binary (named 'clang++' or 'clang++-*'. Must
# satisfy minimum version.
def find_clang_binary(paths, min_version = "14.0.0") : String?
  log %(Searching for binary clang++ or clang++-* in #{paths.join ':'}. Minimum version #{min_version})
  clang_find_config = <<-YAML
  kind: Executable
  try:
    - clang++
    - clang++-*
  search_paths:
    #{paths.map { |p| "- \"" + p + "\"" }.join("\n  ")}
  version:
    min: #{min_version}
    command: "% --version"
    regex: "clang version ([0-9.]+)"
  YAML
  clang_find_config = Bindgen::FindPath::PathConfig.from_yaml clang_find_config

  path_finder = Bindgen::FindPath.new(__DIR__)
  path_finder.find(clang_find_config)
end

# Finds llvm-config binary inside directories in PATH. It must
# satisfy minimum version.
def find_llvm_config_binary(paths = nil, min_version = "14.0.0") : String?
  log %(Searching for binary `llvm-config` or `llvm-config-*` in PATH. Minimum version #{min_version})
  llvm_config_find_config = <<-YAML
  kind: Executable
  try:
    - llvm-config
    - llvm-config-*
  search_paths:
    #{paths.try(&.map { |p| "- \"" + p + "\"" }.join("\n  ")) || ENV["PATH"].split(/:+/).map { |p| "- \"" + p + "\"" }.join("\n  ")}
  version:
    min: "#{min_version}"
    command: "% --version"
    regex: "([0-9.]+)"
  YAML
  llvm_config_find_config = Bindgen::FindPath::PathConfig.from_yaml llvm_config_find_config

  path_finder = Bindgen::FindPath.new(__DIR__)
  path_finder.find(llvm_config_find_config)
end

# Prints help and exits.
def print_help_and_exit
  STDERR.puts <<-END
  You're missing the LLVM and/or Clang executables or development libraries.

  If you've installed the binaries in a non-standard location:
    1) Make sure that `llvm-config` or `llvm-config-*` is set with --llvm_config FILE or is in PATH. The first binary found which satisfies version will be used.
    2) In rare cases if clang++ isn't found or is incorrect, you can also specify it with --clang FILE.

  Static libraries are used if available, shared ones otherwise.  Set env var
  BINDGEN_DYNAMIC=1 or BINDGEN_DYNAMIC=0 to force shared or static linking.

  If you are missing the packages, please install them:
    ArchLinux: pacman -S llvm clang gc libyaml
    Ubuntu: apt install clang-18 libclang-18-dev llvm-18-dev zlib1g-dev libzstd-dev libgc-dev libpcre2-dev
    CentOS: yum install crystal libyaml-devel gc-devel pcre2-devel zlib-devel clang-devel
    openSUSE: zypper install llvm clang libyaml-devel gc-devel pcre2-devel zlib-devel clang-devel ncurses-devel
    Mac OS: brew install crystal bdw-gc gmp libevent libxml2 libyaml llvm
  END

  exit 1
end

# Prints message to STDERR unless --quiet is given
def log(message : String)
  unless OPTIONS[:quiet]
    STDERR.puts message
  end
end

# Logs the command line, then runs it and returns output of the backticks
def log_and_run(cmdline : String)
  log cmdline
  `#{cmdline}`
end

# Shell-split. Helper function used in parsing clang output.
def shell_split(line : String)
  list = [] of String
  skip_next = false
  in_string = false
  offset = 0

  # Parse string
  line.each_char_with_index do |char, idx|
    if skip_next
      skip_next = false
      next
    end

    case char
    when '\\' # Escape character
      skip_next = true
    when ' ' # Split character
      unless in_string
        list << line[offset...idx]
        offset = idx + 1
      end
    when '"' # String marker
      in_string = !in_string
    else
    end
  end

  list.reject(&.empty?).map do |x|
    # Remove surrounding double-quotes
    if x.starts_with?('"') && x.ends_with?('"')
      x[1..-2]
    else
      x
    end
  end
end

# Finds all static LLVM or clang libraries.  We don't need all of them, but
# the linker only picks what's used.
def find_static_libraries(paths, prefix)
  paths
    .flat_map { |path| Dir["#{path}/lib#{prefix}*.a"] }
    .map { |path| File.basename(path)[/^lib(.+)\.a$/, 1] }
    .reject(&.starts_with?("clang_rt")) # Compiler runtime, not part of clang.
    .uniq
end

# Finds the shared LLVM or clang libraries.  If the all-in-one library
# *preferred* exists, only that one is used.
def find_shared_libraries(paths, prefix, preferred)
  suffix = {% if flag?(:darwin) %} "dylib" {% else %} "so" {% end %}

  if paths.any? { |path| File.exists?("#{path}/lib#{preferred}.#{suffix}") }
    return [preferred]
  end

  paths
    .flat_map { |path| Dir["#{path}/lib#{prefix}*.#{suffix}"] }
    .map { |path| File.basename(path)[/^lib(.+)\.#{suffix}$/, 1] }
    .uniq
end

# Gets the list of -l... link arguments.
# Libraries must precede their dependencies. We can use the
# --start-group and --end-group wrappers in linux to get
# the correct order
def get_lib_args(libs_list)
  libs = Array(String).new
  {% if flag? :darwin %}
    libs.concat libs_list.map { |x| "-l#{x}" }
  {% else %}
    libs << "-Wl,--start-group"
    libs.concat libs_list.map { |x| "-l#{x}" }
    libs << "-Wl,--end-group"
  {% end %}
  libs
end

# Header of generated files, using the line comment marker *comment*.
def generated_header(comment)
  "#{comment} Generated by #{__FILE__}\n#{comment} DO NOT CHANGE"
end

# Writes a file only if its contents are different than already present on disk.
# Only write if there's a change.  Else we break make's dependency caching and
# constantly rebuild everything.
def write_if_changed(path, content)
  if !File.exists?(path) || File.read(path) != content
    File.write(path, content)
    return true
  end
  false
end

# Runs the command and arguments as shell command line in backticks.
# Returns it's output.chomp.
def output_of(*args)
  `#{args.map { |r| "\"#{r}\"" }.join ' '}`.chomp
end

# Parses output from clang++ -### ....
def parse_clang_output(output)
  # Untangle the output
  raw_cppflags = output[-2].gsub(/^\s+"|\s+"$/, "")
  raw_ldflags = output[-1].gsub(/^\s+"|\s+"$/, "")

  OPTIONS[:cppflags] = raw_cppflags.split(/"\s+"/)
    .concat(shell_split(ENV.fetch("CPPFLAGS", "")))
    .uniq
  OPTIONS[:ldflags] = raw_ldflags.split(/"\s+"/)
    .concat(shell_split(ENV.fetch("LDFLAGS", "")))
    .uniq

  # Interpret the argument lists
  flags = cppflags + ldflags
  index = 0
  internal_isystem = false
  while index < flags.size
    flag = flags[index]
    if internal_isystem
      if flag[0] == '-'
        internal_isystem = false
      else
        system_include_dirs << flag
        index += 1
        next
      end
    end

    case flags[index]
    when "-internal-isystem"
      internal_isystem = true
    when "-resource-dir" # Find paths on Ubuntu
      resource_dir = flags[index + 1]
      system_include_dirs << File.expand_path("#{resource_dir}/../../../include")
      index += 1
    when "-lto_library"
      to_library = flags[index + 1]
      system_lib_dirs << to_library.split("/lib/")[0] + "/lib/"
      index += 1
    when /^-L/
      l = flags[index][2..-1]
      l += "/" if l !~ /\/$/
      system_lib_dirs << l
    else
    end

    index += 1
  end

  # Check Darwin include dir
  {% if flag? :darwin %}
    if Dir.exists? "/usr/local/include/"
      system_include_dirs << "/usr/local/include"
    end
  {% end %}

  # Need to add the clang includes if we can find them. This is just
  # in case and we don't fear duplicates as they will be sorted out
  # later.
  # The resource directory is named after the major version since LLVM 16.
  {llvm_version, llvm_version.split('.').first}.each do |version|
    system_include_dirs << File.join(llvm_libdir, "clang", version, "include")
  end

  # Clang doesn't necessarily search its own library directory.
  system_lib_dirs.unshift llvm_libdir

  # Clean libs
  system_lib_dirs.uniq!
  system_lib_dirs.map! { |path| File.expand_path(path.gsub(/\/$/, "")) }
  system_lib_dirs.select! { |path| File.directory? path }
  system_include_dirs.uniq!
  system_include_dirs.map! { |path| File.expand_path(path.gsub(/\/$/, "")) }
  system_include_dirs.select! { |path| File.directory? path }
end

# Convenience functions for accessing OPTIONS
def llvm_bindir
  OPTIONS[:llvm_bindir].as String
end

def llvm_libdir
  OPTIONS[:llvm_libdir].as String
end

def clang
  OPTIONS[:clang].as String
end

def llvm_config
  OPTIONS[:llvm_config].as String
end

def llvm_version
  OPTIONS[:llvm_version].as String
end

def cppflags
  OPTIONS[:cppflags].as Array(String)
end

def ldflags
  OPTIONS[:ldflags].as Array(String)
end

def system_include_dirs
  OPTIONS[:system_include_dirs].as Array(String)
end

def system_lib_dirs
  OPTIONS[:system_lib_dirs].as Array(String)
end

def system_libs
  OPTIONS[:system_libs].as Array(String)
end

def clang_libs
  OPTIONS[:clang_libs].as Array(String)
end

def llvm_libs
  OPTIONS[:llvm_libs].as Array(String)
end

def generated_hpp
  OPTIONS[:generated_hpp].as String
end

def variables
  OPTIONS[:variables].as String
end

def spec_base
  OPTIONS[:spec_base].as String
end

def llvm_cxx_flags
  OPTIONS[:llvm_cxx_flags].as String
end

def llvm_ld_flags
  OPTIONS[:llvm_ld_flags].as String
end

log "All done."
exit 0
