module Bindgen
  module Generator
    # Base class for a Generator.  It's used in conjunction of one or several
    # processors to write generated data out to disk.
    abstract class Base
      # Single indention-depth prefix
      INDENTION = "  "

      # Name of the section in a single-file setup.
      SINGLE_FILE_SECTION = ""

      # Complete configuration document
      getter user_config : Configuration

      # Configuration of this generator.
      getter config : Configuration::Generator

      # Output handle.  May change during the life-time of the generator!
      @io : IO

      # Indention depth.  See `#indent`.
      @depth = 0

      # Name of the current output section
      @current_section : String?

      def initialize(@user_config : Configuration, @config : Configuration::Generator, @db : TypeDatabase)
        @io = IO::Memory.new # Dummy IO
      end

      # Publicly accessed method.  Writes *node*, while taking into account that
      # the output may be split among multiple files.  If `io` is not `nil`,
      # it'll be used as output.  This is useful for recursive generator
      # invocations.
      #
      # *depth* is only respected if *io* is not `nil`, in which case it'll
      # override `@depth`.
      def write_all(node : Graph::Container, io : IO? = nil, depth : Int32 = 0)
        single_file_config = false

        if io # Inherit existing IO?
          @io.close
          @io = io
          @depth = depth
          single_file_config = true
        elsif !@config.output.includes?('%') # Single-file configuration
          open_output Util.template(@config.output, replacement: nil)
          single_file_config = true
        end

        if single_file_config
          @current_section = SINGLE_FILE_SECTION
          enter_section SINGLE_FILE_SECTION
        end

        # Hand off to the implementation.
        write(node)

        # Finalize output
        if old_section = @current_section
          leave_section old_section
        end

        # Only close the io if we didn't inherit it.
        @io.close if io.nil?
      end

      # Writes the *node* to the output file(s).  Make sure to call
      # `#begin_section` before writing any data.
      abstract def write(node : Graph::Container)

      # Called by `#begin_section` to enter *section*.  Override if the target
      # language requires special treatment.  If the user configured a
      # single-file output, *section* will be the empty string (`""`).  In this
      # case, the method will only be called once during the life-time of the
      # output.
      protected def enter_section(section)
        nil # Does nothing by default.
      end

      # Called by `#begin_section` to leave *section*.  Override if the target
      # language requires special treatment.  If the user configured a
      # single-file output, *section* will be the empty string (`""`).  In this
      # case, the method will only be called once during the life-time of the
      # output.
      protected def leave_section(section)
        nil # Does nothing by default.
      end

      # Leaves the current section, and enters section *name*.  The output file
      # is changed if configured.
      protected def begin_section(name : String)
        # Check if the user configured a multi-file setup.
        return unless @config.output.includes?('%')
        return if @current_section == name

        # Leave current section
        if old_section = @current_section
          leave_section old_section
        end

        # And open the next output with a file-system-safe name.
        @current_section = name
        partial_name = name.underscore.gsub(/[^a-z0-9_]/i, "_")
        full_path = Util.template(@config.output, partial_name)
        open_output full_path
      end

      # Closes the old `@io`, and opens a new one at *full_path*.  Do not use
      # this method directly, use `#begin_section` instead.
      private def open_output(full_path)
        @io.close
        @io = File.open(full_path, "w")

        if text = @config.preamble
          @io.puts Util.template(text, replacement: nil)
        end
      end

      # Increments the indention depth by one, yields, and decrements the depth
      # afterwards again.
      def indented(&)
        @depth += 1
        yield
      ensure
        @depth -= 1
      end

      # Prints *text* into the current output, adhering to the current indention
      # depth.  Multi-line text is supported, too.
      def puts(text : String)
        indention = INDENTION * @depth
        @io.puts(indention + text.gsub("\n", "\n#{indention}"))
      end
    end
  end
end
