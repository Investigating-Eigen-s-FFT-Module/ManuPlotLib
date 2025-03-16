__precompile__()

module GearshifftEvaluation

include("Common.jl")
include("ParseCli.jl")
include("GearshifftBuilder.jl")
include("Benchmarking.jl")
include("DataProcessing.jl")
include("Plotting.jl")

function main()
    args = parse_commandline()
    benchmark_template_name = args["benchmark_template"]
    plot_template_name = args["plot_template"]
    
    mkpath(CACHE_DIR)
    mkpath(OUTPUT_DIR)
    benchmark_templates = TOML.parsefile(BENCHMARK_TEMPLATES_PATH)
    plot_templates = TOML.parsefile(PLOT_TEMPLATES_PATH)
    if !isnothing(benchmark_template_name)
        tag = args["benchmark_tag"]
        benchmark_template = get_template(benchmark_templates, benchmark_template_name)

        build_hash = build(benchmark_template, benchmark_template_name)
        tag = get(args, "benchmark_tag", nothing)

        run_hash = run_benchmark(benchmark_template, benchmark_template_name, build_hash, tag)
        @info "Finished benchmark with hash: '$run_hash'"
    end
    
    if !isnothing(plot_template_name)
        tag = args["plot_tag"]
        plot_template = get_template(plot_templates, plot_template_name)
        plot_hash = create_plot(plot_template, plot_template_name, benchmark_templates, tag)
        @info "Finished plot with hash: '$plot_hash'"
    end
end
end # module GearshifftEvaluation
