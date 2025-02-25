using ArgParse
using TOML

# Possible FFT implementations in gearshifft (todo: extend if applicable)
gearshifft_impl = [:fftw, :eigen_fftw, :eigen_kissfft,
                   :eigen_mkl, :eigen_pocketfft]

# Load default config values
function load_config()::Dict
    config_path = joinpath(@__DIR__, "..", "config", "config.toml")
    return TOML.parsefile(config_path)
end

# Parse commandline arguments
function parse_commandline()
    config = load_config() # default values that may be overridden
    default_paths = config["paths"]

    s = ArgParseSettings(
        description = "GearshifftEvaluation - Benchmark and plot FFT implementations with Gearshifft",
        commands_are_required = false,
        exc_handler = ArgParse.debug_handler
    )
    s.autofix_names = true

    add_arg_group!(s, "required arguments", :req_arg, false, required = true)
    add_arg_group!(s, "main actions", :actions, false, required = true)
    add_arg_group!(s, "benchmark options", :benchmark_opt, false)
    add_arg_group!(s, "plotting options", :plot_opt, false)

    @add_arg_table! s begin
        "--implementation", "-I"
            help = "Choose FFT implementation"
            required = true
            arg_type = Symbol
            range_tester = in(gearshifft_impl)
            group = :req_arg
        "--benchmark", "-B"
            help = "Run a new benchmark"
            action = :store_true
            group = :actions
        "--benchmark-template", "-b"
            help = "Pick a benchmark template from templates/benchmark_templates.toml"
            arg_type = String
            default = "default"
            group = :benchmark_opt
        "--plot", "-P"
            help = "Create a new plot"
            action = :store_true
            group = :actions
        "--plot-template", "-p"
            help = "Pick a plot template from templates/plot_templates.toml"
            arg_type = String
            default = "default"
            group = :plot_opt
        "--benchmark-id", "-i" # todo: not sure yet how to ID benchmarks, revise
            help = "id of benchmark to plot (defaults to newest generated)"
            default = :default
            group = :plot_opt
        "--gearshifft-root"
            help = "root directory of gearshifft repo"
            arg_type = String
            default = default_paths["gearshifft_root"]
        "--gearshifft-binaries"
            help = "location of gearshifft binaries (relative to gearshifft root)"
            arg_type = String
            default = default_paths["gearshifft_bin_dir"]
        "--output-dir", "-o"
            help = "location of program results (benchmarks/plots)"
            arg_type = String
            default = default_paths["output_dir"]
        "--cache-dir", "-c"
            help = "location of temporary files (e.g. last used benchmark template)"
            arg_type = String
            default = default_paths["cache_dir"]
    end
    return parse_args(s)
end