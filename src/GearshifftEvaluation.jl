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
    benchmark_templates_dir = joinpath(root, "templates", "benchmark_templates.toml")
    cache_dir = joinpath(root, args["cache_dir"])
    gearshifft_root = joinpath(root, args["gearshifft_root"])
    output_dir = joinpath(root, args["output_dir"])
    fft_implementation = args["implementation"]
    
    mkpath(cache_dir)
    mkpath(output_dir)
    if args["benchmark"]
        println("Running benchmark with implementation: $(args["implementation"])")

        build_hash = build(args["benchmark_template"], gearshifft_root, cache_dir, benchmark_templates_dir)
        
        run_hash = run_benchmark(fft_implementation, build_hash, args["benchmark_template"],
                                 gearshifft_root, cache_dir, benchmark_templates_dir, output_dir)
    end
    
    if args["plot"]
        println("Creating plot for implementation: $(args["implementation"])")
        # Add plotting logic here
    end
end
end # module GearshifftEvaluation
