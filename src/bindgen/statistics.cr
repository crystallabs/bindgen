module Bindgen
  # Simple collector of run-time statistics.
  class Statistics
    # Stores timing data of a measured stage.
    struct Timing
      # The duration of this statistic
      getter duration : Time::Span

      # If the executed block returned a `Statistics`, it'll be recorded here.
      getter child : Statistics?

      # Heap size change, in bytes.
      getter heap_size_change : Int64

      def initialize(@duration, @heap_size_change, @child = nil)
      end
    end

    DEPTH_MULTIPLIER = 2
    JUSTIFY_OFFSET   = 2
    HEAP_COLUMN_SIZE = 8

    # Collected stages
    getter stages = {} of String => Timing

    # Garbage collector statistics *before* any measures.
    getter before : GC::Stats

    # Garbage collector statistics *after* the measures.  Only available after
    # calling `#finish!`
    getter! after : GC::Stats?

    def initialize
      @before = GC.stats
    end

    # Finishes the statistics collection.
    def finish! : self
      @after = GC.stats if @after.nil?
      self
    end

    # Measures execution of the given block.  Returns the result of the block.
    # The measured data is put into `#stages`.
    def measure(stage_name : String)
      before_gc = GC.stats
      before = Time.local
      result = yield
      after = Time.local
      after_gc = GC.stats

      duration = after - before
      child = result.finish! if result.is_a?(Statistics)

      heap_size = after_gc.heap_size.to_i64 - before_gc.heap_size.to_i64
      @stages[stage_name] = Timing.new(duration, heap_size, child)
      result
    end

    # Returns the total duration of all measured steps.  The timings between the
    # stages is *not* recorded, and is thus excluded from the total duration.
    def total_duration : Time::Span
      @stages.values.sum(Time::Span::ZERO, &.duration)
    end

    # Returns how much the heap size has changed during the measurements
    def heap_size_change : Int64
      after.heap_size.to_i64 - @before.heap_size.to_i64
    end

    # Returns a formatted human-readable string.
    def to_s(depth : Int32) : String
      String.build do |b|
        to_s(b, depth)
      end
    end

    # Returns the maximum length of all names recursively.  Used to justify the
    # output table correctly.
    protected def max_name_length(depth)
      @stages.max_of do |name, timing|
        name_size = depth * DEPTH_MULTIPLIER + name.size
        child_size = 0

        if child = timing.child
          child_size = child.max_name_length(depth + 1)
        end

        {name_size, child_size}.max
      end
    end

    # Generates the table header
    private def table_header(justification, indent)
      header = {
        indent,
        "Stage".ljust(justification - indent.size),
        "Heap".ljust(HEAP_COLUMN_SIZE),
        " Duration",
      }

      header.join.colorize.mode(:bold)
    end

    # Writes formatted human-readable data into *io*.
    def to_s(io, depth = 0, justification = nil)
      indent = " " * (depth * DEPTH_MULTIPLIER)

      if justification.nil? # Is this the first invocation?
        justification = max_name_length(depth) + JUSTIFY_OFFSET
        io << table_header(justification, indent) << "\n"
      end

      total = total_duration

      @stages.each do |name, timing|
        duration = timing.duration
        percent = ((duration / total) * 100).to_i
        child = timing.child
        heap_size_change = timing.heap_size_change
        heap_size_change = child.heap_size_change if child

        print_name = name.ljust(justification - indent.size)
        io << indent << print_name
        io << Util.format_bytes(heap_size_change, true).ljust(HEAP_COLUMN_SIZE) << " "
        timing.duration.inspect(io)
        io << " " << percent << "% \n"

        if child
          child.to_s(io, depth + 1, justification)
        end
      end

      io
    end
  end
end
