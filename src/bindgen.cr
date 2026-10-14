# This is the main file running the `bindgen` program.
# If you want use bindgen as library, require "bindgen/library" instead.
require "./bindgen/library"

require "toka"

class CliOptions
  Toka.mapping({
    stats: { # --stats, -s
      type:        Bool,
      default:     false,
      description: "Show runtime statistics",
    },
    debug: { # --debug, -d
      type:        Bool,
      default:     false,
      description: "Print debug logging",
    },
    trace: { # --trace, -t
      type:        Bool,
      default:     false,
      description: "Print trace logging",
    },
    var: { # --var, -v
      type:        Hash(String, String),
      value_name:  "NAME=VALUE",
      description: "Add variable.  Overrides builtins.",
    },
    chdir: { # Hack to make Crystal find paths by itself.
      type:        String?,
      description: "Change into the directory before proceeding",
      short:       false,
    },
  }, {
    banner: "bindgen [options] <configuration.yml>",
    footer: "See https://github.com/Papierkorb/bindgen for further information.",
  })
end

opts = CliOptions.new

if opts.positional_options.size < 1
  puts Toka::HelpPageRenderer.new(CliOptions)
  exit 1
elsif opts.positional_options.size > 1
  puts "Exactly one configuration file must be supplied.  See --help."
  exit 1
end

# Log to standard output, one colored line per entry.
Log.define_formatter LogFormat,
  "#{timestamp} #{severity} - #{source(after: ": ")}#{message}" \
  "#{data(before: " -- ")}#{context(before: " -- ")}#{exception}"

LOG_COLORS = {
  Log::Severity::Trace  => :cyan,
  Log::Severity::Debug  => :blue,
  Log::Severity::Info   => :green,
  Log::Severity::Notice => :magenta,
  Log::Severity::Warn   => :yellow,
  Log::Severity::Error  => :light_red,
  Log::Severity::Fatal  => :red,
}

log_level = if opts.trace
              Log::Severity::Trace
            elsif opts.debug
              Log::Severity::Debug
            else
              Log::Severity::Error
            end

log_formatter = Log::Formatter.new do |entry, io|
  Colorize.with.colorize(LOG_COLORS[entry.severity]? || :default).surround(io) do
    LogFormat.format(entry, io)
  end
end

Log.setup(log_level, Log::IOBackend.new(STDOUT, formatter: log_formatter, dispatcher: :sync))

# Merge additional --var's
Bindgen::Variables.builtin.merge!(opts.var)

if working_directory = opts.chdir
  Dir.cd(working_directory)
end

# Parse the configuration
config_path = opts.positional_options.first
config = Bindgen::ConfigReader.from_file(
  klass: Bindgen::Configuration,
  path: config_path,
)

# And off we go!
tool = Bindgen::Tool.new(File.dirname(config_path), config, opts.stats)
exit_code = tool.run!
exit exit_code
