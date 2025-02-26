module GearshifftEvaluation

include("Benchmarking.jl")
include("DataProcessing.jl")
include("GearshifftBuilder.jl")
include("ParseCli.jl")
include("Plotting.jl")

function main()
    args = parse_commandline()
    root = joinpath(@__DIR__, "..")
    benchmark_templates_path = joinpath(root, "templates", "benchmark_templates.toml")
    cache_path = joinpath(root, args["cache_dir"])
    gearshifft_root = joinpath(root, args["gearshifft_root"])
    
    mkpath(cache_path)
    if args["benchmark"]
        println("Running benchmark with implementation: $(args["implementation"])")
        
        build(args["benchmark_template"], gearshifft_root, cache_path, benchmark_templates_path)
        # Add benchmark logic here
    end
    
    if args["plot"]
        println("Creating plot for implementation: $(args["implementation"])")
        # Add plotting logic here
    end
end
end # module GearshifftEvaluation
