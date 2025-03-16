using ArgParse
using TOML

# Parse commandline arguments
function parse_commandline()

    s = ArgParseSettings(
        description = "GearshifftEvaluation - Benchmark and plot FFT implementations with Gearshifft",
        commands_are_required = false,
        exc_handler = ArgParse.debug_handler
    )
    s.autofix_names = true

    add_arg_group!(s, "main actions", :actions, false, required = true)
    add_arg_group!(s, "benchmark options", :benchmark_opt, false)
    add_arg_group!(s, "plotting options", :plot_opt, false)

    @add_arg_table! s begin
        "--benchmark-template", "-b"
            help = "Run a benchmark template from templates/benchmark_templates.toml"
            arg_type = String
            default = nothing
            group = :actions
        "--plot-template", "-p"
            help = "Run a plot template from templates/plot_templates.toml"
            arg_type = String
            default = nothing
            group = :actions
        "--benchmark-tag", "-t" 
            help = "Specify a custom tag in the output csv (line 1); Default is benchmark template hash and datetime"
            group = :benchmark_opt
        "--plot-tag", "-T"
            help = "Specify a regex pattern to filter output csv files by their tag (in metadata of csv)"
            default = nothing
    end
    args = try
        parse_args(s)
    catch e
        @error e.text
        @info "See ./gearshifft-eval -h for usage details"
        exit(1)
    end
    return args
end