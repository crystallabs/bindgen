#!/usr/bin/env crystal run

# This is a helper script. It requires `llvm-config` to point to the
# LLVM version which is to be used.
# It asks llvm-config for LLVM's directories and flags, and clang for its
# resource directory and for the include paths of the C++ standard library.

# As part of the run, it generates some files, among them `variables.cmake`
# with the LLVM and Clang libraries to link to, which CMake includes.
# Provides diagnostics to standard error.
# This script is called automatically by CMake.
# Can be invoked manually. Invoke with --help for options.

require "option_parser"
require "yaml"
require "../src/bindgen/util"
require "../src/bindgen/find_path"

# Parse command line options. Each of these options has an accessor
# function of the same name, defined at the end of file.
OPTIONS = Hash(Symbol, Bool | String | Array(String)?).new
OPTIONS[:clang] = nil
OPTIONS[:llvm_config] = nil
OPTIONS[:print_llvm_libs] = false
OPTIONS[:print_clang_libs] = false
OPTIONS[:quiet] = false
OPTIONS[:debug] = false
OPTIONS[:system_include_dirs] = [] of String
OPTIONS[:system_libs] = [] of String
OPTIONS[:output_dir] = __DIR__
OPTIONS[:spec_base] = File.expand_path "#{__DIR__}/../spec/integration/spec_base.yml"
parse_cli_args

# Files of the build, kept apart for each build directory.
OPTIONS[:generated_hpp] = File.expand_path "#{output_dir}/include/generated.hpp"
OPTIONS[:variables] = File.expand_path "#{output_dir}/variables.yml"
OPTIONS[:cmake_variables] = File.expand_path "#{output_dir}/variables.cmake"

# The static Clang libraries the tool is linked against: The ones it uses, and
# those they depend on.  Which of these exist depends on the LLVM version.
CLANG_LIBS = %w[
  clangTooling clangToolingCore clangToolingInclusions clangFormat
  clangFrontend clangDriver clangDependencyScanning
  clangScalableStaticAnalysisAnalyses
  clangScalableStaticAnalysisSourceTransformation
  clangScalableStaticAnalysisCore clangUnifiedSymbolResolution clangOptions
  clangParse clangSerialization
  clangSema clangAPINotes clangAnalysis clangAnalysisLifetimeSafety
  clangASTMatchers clangEdit clangRewrite clangAST clangLex clangBasic
  clangSupport
]

# The LLVM components these Clang libraries use.  Which of these exist
# depends on the LLVM version, too.
LLVM_COMPONENTS = %w[
  support option core mc mcparser object binaryformat bitreader
  bitstreamreader demangle profiledata remarks targetparser windowsdriver
  frontendopenmp frontendhlsl plugins
]

# Link against LLVM's shared rather than static libraries?  Auto-detected below
# if unset.
dynamic = ENV["BINDGEN_DYNAMIC"]?.presence.try(&.==("1"))

# Extra flags for clang++ when asking it for the C++ standard library and when
# building the specs, e.g. `-stdlib=libc++`.
OPTIONS[:clang_flags] = ENV["BINDGEN_CLANG_FLAGS"]? || ""

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
OPTIONS[:llvm_includedir] = output_of(OPTIONS[:llvm_config], "--includedir")

# The clang++ belonging to that LLVM installation
OPTIONS[:clang] ||= File.join(llvm_bindir, "clang++")
unless File::Info.executable?(clang)
  log "Cant find clang at #{clang}"
  print_help_and_exit
end
log "Using clang binary in #{OPTIONS[:clang].inspect}. Querying it."

# Ask clang for the paths only it knows.
OPTIONS[:resource_dir] = output_of(clang, "-print-resource-dir")
OPTIONS[:system_include_dirs] = find_system_include_dirs

# Now extract clang and llvm-specific libs.  Static libraries are preferred if
# both kinds are available, but the two kinds are never mixed.
static_clang_libs = CLANG_LIBS.select { |name| File.exists?("#{llvm_libdir}/lib#{name}.a") }
has_static_llvm = File.exists?("#{llvm_libdir}/libLLVMSupport.a")
dynamic = static_clang_libs.empty? || !has_static_llvm if dynamic.nil?
log "Linking LLVM and Clang #{dynamic ? "dynamically" : "statically"}. (Adjust with env BINDGEN_DYNAMIC=0/1 if needed)"

if dynamic
  OPTIONS[:clang_libs] = find_shared_libraries(llvm_libdir, "clang", "clang-cpp")
  OPTIONS[:llvm_libs] = find_shared_libraries(llvm_libdir, "LLVM", "LLVM")
else
  OPTIONS[:clang_libs] = static_clang_libs
  # llvm-config adds the libraries these components depend on.
  components = output_of(llvm_config, "--components").split & LLVM_COMPONENTS
  log "Using LLVM components #{components.join ' '}"
  OPTIONS[:llvm_libs] = output_of(llvm_config, "--link-static", "--libs", components).split.map(&.lchop("-l"))
  # Static LLVM libraries don't pull in their own dependencies.
  OPTIONS[:system_libs] = output_of(llvm_config, "--link-static", "--system-libs", components).split
end

# Fall back to what llvm-config says if no LLVM library was found.
if llvm_libs.empty?
  log "Cannot find LLVM libs in #{llvm_libdir}, asking llvm-config."
  link_mode = dynamic ? "--link-shared" : "--link-static"
  OPTIONS[:llvm_libs] = output_of(llvm_config, link_mode, "--libs", "all").split.map(&.lchop("-l"))
end

# See if only partial info was requested:

if OPTIONS[:debug]
  pp OPTIONS # ameba:disable Lint/DebugCalls
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

# Generate variables.cmake file, which is included by crystal.cmake
log "Generating #{cmake_variables}"
write_if_changed(cmake_variables, String.build do |b|
  b.puts generated_header("#")
  b.puts
  b.puts cmake_set("clang_libs", get_lib_args(clang_libs))
  b.puts cmake_set("llvm_libs", get_lib_args(llvm_libs))
  b.puts cmake_set("system_libs", system_libs)
end)

# Generate spec_base.yml
log "Generating #{spec_base}"
spec_base_content = {
  module:     "Test",
  generators: {
    cpp: {
      output: "tmp/{SPEC_NAME}.cpp",
      build:  "#{clang} #{clang_flags} #{spec_cxx_flags} #{system_include_dirs.map { |x| "-I#{File.expand_path(x)}" }.join(' ')}" \
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
  library: "%/tmp/{SPEC_NAME}.o #{cxx_stdlib_link_flags}",
  parser:  {
    files:    ["{SPEC_NAME}.cpp"],
    includes: [
      "%",
    ].concat(system_include_dirs),
    # Parse in the C++ standard the specs are built in.
    flags: ["-x", "c++", spec_cxx_standard],
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
    parser.on("--clang PATH", "Path to clang binary (default: clang++ in llvm bindir)") { |path| OPTIONS[:clang] = path }
    parser.on("--output-dir DIR", "Where to write generated.hpp, variables.yml and variables.cmake (default: clang/)") { |dir| OPTIONS[:output_dir] = dir }
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
      #{paths.try(&.map { |path| "- \"" + path + "\"" }.join("\n  ")) || ENV["PATH"].split(/:+/).map { |path| "- \"" + path + "\"" }.join("\n  ")}
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

    Set env var BINDGEN_CLANG_FLAGS to pass extra flags to clang++, for example
    -stdlib=libc++ to use that C++ standard library instead of the default one.

    If you are missing the packages, please install them:
      ArchLinux: pacman -S llvm clang gc libyaml
      Ubuntu: apt install clang-18 libclang-18-dev llvm-18-dev zlib1g-dev libzstd-dev libgc-dev libpcre2-dev
      CentOS: yum install crystal libyaml-devel gc-devel pcre2-devel zlib-devel clang-devel
      openSUSE: zypper install llvm clang libyaml-devel gc-devel pcre2-devel zlib-devel clang-devel ncurses-devel
      macOS: brew install crystal llvm pcre2 bdw-gc
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

# Finds the include directories of LLVM, of the C++ standard library and of
# clang itself.
def find_system_include_dirs
  dirs = [llvm_includedir]

  # Only clang knows where the C++ standard library and the C headers are.  Its
  # driver passes these directories to the compiler proper as
  # `-internal-isystem` and `-internal-externc-isystem`, in search order.
  output = log_and_run("#{clang} #{clang_flags} -### -fsyntax-only #{__DIR__}/src/bindgen.cpp 2>&1")
  unless cc1 = output.lines.reverse!.find(&.includes?(%("-cc1")))
    STDERR.puts %(Unexpected output from "#{clang}": Found no compiler invocation.)
    exit 1
  end

  flags = cc1.gsub(/^\s*"|"\s*$/, "").split(/"\s+"/)
  flags.each_cons_pair do |flag, value|
    dirs << value if flag.in?("-internal-isystem", "-internal-externc-isystem")
  end

  # Homebrew's include directories (Apple Silicon and Intel)
  {% if flag? :darwin %}
    dirs << "/opt/homebrew/include" << "/usr/local/include"
  {% end %}

  # Clang's own headers, in case they weren't among the above.
  dirs << File.join(resource_dir, "include")

  dirs
    .map { |path| File.expand_path(path.rchop('/')) }
    .uniq!
    .select { |path| File.directory? path }
end

# Finds the shared LLVM or clang libraries in *dir*.  If the all-in-one
# library *preferred* exists, only that one is used.
def find_shared_libraries(dir, prefix, preferred)
  suffix = {% if flag?(:darwin) %} "dylib" {% else %} "so" {% end %}

  return [preferred] if File.exists?("#{dir}/lib#{preferred}.#{suffix}")

  Dir["#{dir}/lib#{prefix}*.#{suffix}"]
    .map { |path| File.basename(path)[/^lib(.+)\.#{suffix}$/, 1] }
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

# Builds a CMake command setting the variable *name* to the list *values*.
def cmake_set(name, values)
  quoted = values.map { |value| %("#{value.gsub(/[\\"$;]/) { |char| "\\#{char}" }}") }
  "set(#{name} #{quoted.join(' ')})"
end

# Writes a file only if its contents are different than already present on disk.
# Only write if there's a change.  Else we break make's dependency caching and
# constantly rebuild everything.
def write_if_changed(path, content)
  if !File.exists?(path) || File.read(path) != content
    Dir.mkdir_p(File.dirname(path))
    File.write(path, content)
    return true
  end
  false
end

# Runs the command and arguments as shell command line in backticks.
# Arrays among the arguments are flattened.  Returns its output.chomp.
def output_of(*args)
  `#{args.to_a.flatten.map { |arg| "\"#{arg}\"" }.join " "}`.chomp
end

# Convenience functions for accessing OPTIONS
def llvm_bindir
  OPTIONS[:llvm_bindir].as String
end

def llvm_libdir
  OPTIONS[:llvm_libdir].as String
end

def clang_flags
  OPTIONS[:clang_flags].as String
end

# Linker flags for the C++ standard library the specs are built against.
# LLVM's libc++ isn't necessarily in the default library search path.  Not
# every libc++.so pulls in libc++abi (apt.llvm.org's doesn't), so name it.
def cxx_stdlib_link_flags
  if clang_flags.includes?("-stdlib=libc++")
    "-L#{llvm_libdir} -Wl,-rpath,#{llvm_libdir} -lc++ -lc++abi"
  else
    "-lstdc++"
  end
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

def llvm_includedir
  OPTIONS[:llvm_includedir].as String
end

def resource_dir
  OPTIONS[:resource_dir].as String
end

def system_include_dirs
  OPTIONS[:system_include_dirs].as Array(String)
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

def output_dir
  OPTIONS[:output_dir].as String
end

def cmake_variables
  OPTIONS[:cmake_variables].as String
end

def spec_base
  OPTIONS[:spec_base].as String
end

def llvm_cxx_flags
  OPTIONS[:llvm_cxx_flags].as String
end

# The C++ standard the specs are built and parsed in: the one of
# `llvm_cxx_flags`, but at least C++17, which the specs use, like
# `std::optional`.  The `--cxxflags` of LLVM up to 15 say C++14, the default of
# its clang.
def spec_cxx_standard
  standard = llvm_cxx_flags.split.find(&.starts_with?("-std="))
  if standard.nil? || standard =~ /^-std=(gnu|c)\+\+(98|03|0x|11|1y|14)$/
    "-std=c++17"
  else
    standard
  end
end

# `llvm_cxx_flags`, in the standard of `spec_cxx_standard`.
def spec_cxx_flags
  flags = llvm_cxx_flags.split.reject(&.starts_with?("-std="))
  (flags << spec_cxx_standard).join(" ")
end

def llvm_ld_flags
  OPTIONS[:llvm_ld_flags].as String
end

log "All done."
exit 0
