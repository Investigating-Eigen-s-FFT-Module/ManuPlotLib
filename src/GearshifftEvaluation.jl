module GearshifftEvaluation

include("Common.jl")
include("ParseCli.jl")
include("GearshifftBuilder.jl")
include("Benchmarking.jl")
include("DataProcessing.jl")
include("Plotting.jl")

function main()
    args = parse_commandline()
    root = joinpath(@__DIR__, "..")
    benchmark_templates_path = joinpath(root, "templates", "benchmark_templates.toml")
    plot_templates_path = joinpath(root, "templates", "plot_templates.toml")
    cache_dir = joinpath(root, args["cache_dir"])
    gearshifft_root = joinpath(root, args["gearshifft_root"])
    output_dir = joinpath(root, args["output_dir"])
    benchmark_template_name = args["benchmark_template"]
    plot_template_name = args["plot_template"]
    
    mkpath(cache_dir)
    mkpath(output_dir)
    benchmark_templates = TOML.parsefile(benchmark_templates_path)
    if !isnothing(benchmark_template_name)
        benchmark_template = get_template(benchmark_templates, benchmark_template_name)

        build_hash = build(benchmark_template, benchmark_template_name, gearshifft_root, cache_dir)
        tag = get(args, "benchmark_tag", nothing)

        run_hash = run_benchmark(benchmark_template, benchmark_template_name, build_hash,
                      gearshifft_root, cache_dir, output_dir, tag)
        @info "Finished benchmark with hash: '$run_hash'"
    end
    
    if !isnothing(plot_template_name)
        plot_template = get_template(TOML.parsefile(plot_templates_path), plot_template_name)
        create_plot(plot_template, plot_template_name, output_dir, benchmark_templates)
    end
end
end # module GearshifftEvaluation
