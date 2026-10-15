module Bindgen
  module Parser
    Log = ::Log.for(self)

    # Runner for the Clang part.  The path can also be configured through the
    # `BINDGEN_BIN` environment variable.
    class Runner
      Log = ::Log.for(self)

      # Default path to the binary
      BINARY_PATH = File.expand_path("#{File.dirname(__FILE__)}/../../../clang/parser")

      @binary_path : String

      # *project_root* must be a path to the directory the configuration YAML
      # resides.
      def initialize(
        @classes : Array(String), @enums : Array(String), @macros : Array(String),
        @functions : Array(String), @config : Configuration, @project_root : String,
      )
        @binary_path = ENV["BINDGEN_BIN"]? || @config.binary || BINARY_PATH

        Log.info &.emit "new runner", binary_path: @binary_path
      end

      # Arguments for the tool binary
      def arguments(input_file)
        classes = @classes.flat_map { |x| ["-c", Process.quote(x)] }
        enums = @enums.flat_map { |x| ["-e", "#{x}"] }
        flags = @config.flags.map { |x| Util.template(x, replacement: nil) }
        flags << "-fparse-all-comments" if @config.all_comments?
        defines = @config.defines.map { |x| "-D#{x}" }
        includes = template_include_paths.map { |x| "-I#{x}" }
        macros = ["-m", @macros.join('|').inspect]
        functions = ["-f", @functions.join('|').inspect]

        [input_file] + classes + enums + macros + functions + ["--"] + flags + defines + includes
      end

      # Calls the clang tool and returns its output as string.
      def run : String
        Log.info { "start" }
        generate_source_file do |file|
          binary_path = File.expand_path Util.template(@binary_path, replacement: nil)
          command = "#{binary_path} #{arguments(file).join(" ")}"
          Log.trace { "Runner command: #{command}" }
          puts "Runner command: #{command}" if ENV["VERBOSE"]?
          result = `#{command}`
          raise "clang/parser failed to execute." unless $?.success?
          Log.info { "end" }
          result
        end
      end

      # Calls the clang tool and directly parses its output
      def run_and_parse : Document
        Document.parse(run)
      end

      # Generates a dummy C++ header file, which `#include`s all given files
      private def generate_source_file(&)
        file = File.tempfile("bindgen")

        begin
          @config.files.each do |path|
            path = Util.template(path, replacement: nil)
            file.puts %{#include #{path.inspect}}
          end

          file.puts %{#include "#{File.expand_path "#{__DIR__}/../../../assets/parser_helper.hpp"}"}
          @classes.each_with_index do |klass, index|
            file.puts %[template class BindgenTypeInfo<#{klass} >;]

            # Class template instantiations are named through their index.
            if Util.template_instantiation?(klass)
              file.puts %[template struct BindgenInstantiation<#{index}, #{klass} >;]
            end
          end

          file.flush
          yield file.path
        ensure
          file.close
        end
      end

      # Returns the `-I` paths with template expansion to the project root.
      private def template_include_paths
        @config.includes.map do |path|
          Util.template(path, @project_root)
        end
      end
    end
  end
end
