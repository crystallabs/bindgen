require "../spec_helper"

# Line prefixes to look out for in `.relocate_line_reports`
SPEC_METHODS = {"it(", "context(", "describe("}

Spec.before_suite do
  clean_integration
end

def clean_integration
  system "./spec/integration/tmp/clean.sh"
end

# Builds the project in configuration `NAME.yml`, expecting to yield the files
# `tmp/NAME.cr`, `tmp/NAME.cpp` and `tmp/NAME.o`.  Additionally, this macro will
# capture the block given to it and write it into `tmp/NAME_test.cr` within a
# small test skeleton.  Write normal `spec` it-tests in it.
#
# This is magic.  Have a look at the `*_spec.cr` files as sample code.
#
# With *multi_file*, or `BINDGEN_SPEC_MULTI_FILE` set in the environment, the
# C++ code is generated as a file per class, `tmp/NAME.CLASS.cpp`, which are
# built and linked into `tmp/NAME.o`.
macro build_and_run(name, multi_file = false, start = __LINE__, stop = __END_LINE__, source = __FILE__)
  build_and_run_impl({{ name }}, {{ start }}, {{ stop }} - 1, {{ source }}, {{ multi_file }})
end

# Changes the C++ generator of *config* to write a file per class.  Each of
# them includes the spec's C++ file, so a function defined in it out-of-line
# is in every object: the linker is told to keep one.  Apple's linker can't,
# there the spec's C++ file must define its functions `inline`.
private def use_multi_file_output(config)
  cpp = config.generators["cpp"]? || return # A C-only spec
  build = cpp.build || raise "BUG: The C++ generator has no build command"

  compile = build.sub("{SPEC_NAME}.o", %["$(basename "$f" .cpp).o"]).sub("{SPEC_NAME}.cpp", %["$f"])
  cpp.output = cpp.output.sub(/\.cpp$/, ".%.cpp")
  keep_one = {% if flag?(:darwin) %} "" {% else %} "-z muldefs " {% end %}
  cpp.build = "for f in {SPEC_NAME}.*.cpp; do #{compile} || exit 1; done && ld -r #{keep_one}-o {SPEC_NAME}.o {SPEC_NAME}.*.o"
end

# Injects a `describe` block just before the first test-case.  This way, we can
# conveniently define classes first, and specs immediately after that.  The
# indention depth is pretty large already, so every 2-spaces count visually.
private def inject_describe_block(code, name)
  if match = /^ +(?:it|context|describe)[ (]/m.match(code)
    pos = match.begin(0)
    range = pos...pos
    code.sub(range, %<describe "Online test of #{name}" do >) + "\nend"
  else
    <<-CRYSTAL
      describe "Online test of #{name}" do
        #{code}
      end
      CRYSTAL
  end
end

# Embeds *code* into a `spec` skeleton.  Automatically requires the generated
# crystal wrapper of *name*.
private def embedded_test_code(name, code)
  <<-CRYSTAL
    require "spec"
    require "./#{name}"

    #{code}
    CRYSTAL
end

# Prepends a `#<loc..>` pragma to *code*, pointing at *file* on line *base*.
# This will make the online spec point back to the original file.
private def relocate_line_reports(code, file, base)
  "#<loc:#{file.inspect},#{base},1>\n#{code}"
end

# The log of the last tool run by `.run_tool`.
module ToolLog
  class_property warnings = [] of String
end

# Runs the *tool* of `NAME.yml`, and prints its warnings and errors if it fails.
# They go to the default log backend too, but that one is asynchronous and
# doesn't say which spec logged them.  The messages of the warnings are kept in
# `ToolLog.warnings`, for a spec to check.
def run_tool(tool, name) : Int32
  log = Log::MemoryBackend.new
  Log.builder.bind("bindgen.*", :warn, log)

  code = begin
    tool.run!
  ensure
    Log.builder.unbind("bindgen.*", :warn, log)
  end

  ToolLog.warnings = log.entries.select(&.severity.warn?).map(&.message)

  unless code == 0
    puts "#{">>> Log of failed tool run:".colorize.mode(:bold)} #{name}.yml"
    log.entries.each do |entry|
      STDERR.puts "#{entry.severity} - #{entry.source}: #{entry.message}"
      if ex = entry.exception
        STDERR.puts ex.inspect_with_backtrace
      end
    end
  end

  code
end

# Implementation helper for `.build_and_run`.
def build_and_run_impl(name, source_start, source_end, source_file, multi_file = false)
  config_file = "#{__DIR__}/#{name}.yml"
  test_file = "#{__DIR__}/tmp/#{name}_test.cr"

  # Write live test.  Read the source from the input file, so we keep the exact
  # formatting.  Else, the line reporting will point anywhere, but not where we
  # want them.
  code = File.read(source_file).lines[source_start...source_end].join("\n")
  code = relocate_line_reports(code, source_file, source_start)
  code = inject_describe_block(code, name)
  File.write(test_file, embedded_test_code(name, code))

  # Run bindgen tool
  config = Bindgen::ConfigReader.from_file Bindgen::Configuration, config_file
  use_multi_file_output(config) if multi_file || ENV["BINDGEN_SPEC_MULTI_FILE"]?.presence
  tool = Bindgen::Tool.new(__DIR__, config, show_stats: false)

  status = nil
  command = %<crystal run #{test_file} -- --verbose>
  output = IO::Memory.new

  # Run the tool and then the test program
  Dir.cd(__DIR__) do
    ENV["SPEC_NAME"] = name # For later access from the `.yml`
    run_tool(tool, name).should eq(0)
    status = Process.run(command, shell: true, output: output, error: output)
  end

  raise "BUG: Status shouldn't be nil here" if status.nil?

  # On failure, print the output of the failed spec call.
  unless status.success?
    puts "#{">>> Output of failed spec:".colorize.mode(:bold)} #{name}.yml"
    STDERR.write output.to_slice
    puts "#{"<<< Failed spec command:".colorize.mode(:bold)} #{command}"

    raise Spec::AssertionFailed.new("Test for #{name}.yml failed, see above", source_file, source_start)
  end

  # If we reach this line, the inner spec was successful - Yay!
end
