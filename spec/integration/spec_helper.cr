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
macro build_and_run(name, start = __LINE__, stop = __END_LINE__, source = __FILE__)
  build_and_run_impl({{ name }}, {{ start }}, {{ stop }} - 1, {{ source }})
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
    %<describe "Online test of #{name}" do
        #{code}
      end>
  end
end

# Embeds *code* into a `spec` skeleton.  Automatically requires the generated
# crystal wrapper of *name*.
private def embedded_test_code(name, code)
  %<require "spec"
    require "./#{name}"

    #{code}>
end

# Prepends a `#<loc..>` pragma to *code*, pointing at *file* on line *base*.
# This will make the online spec point back to the original file.
private def relocate_line_reports(code, file, base)
  "#<loc:#{file.inspect},#{base},1>\n#{code}"
end

# Implementation helper for `.build_and_run`.
def build_and_run_impl(name, source_start, source_end, source_file)
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
  tool = Bindgen::Tool.new(__DIR__, config, show_stats: false)

  status = nil
  command = %<crystal run --link-flags "-lgccpp" #{test_file} -- --verbose>
  output = IO::Memory.new

  # Run the tool and then the test program
  Dir.cd(__DIR__) do
    ENV["SPEC_NAME"] = name # For later access from the `.yml`
    tool.run!.should eq(0)
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
