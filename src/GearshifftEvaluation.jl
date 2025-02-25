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
    gearshifft_path = joinpath(root, args["gearshifft_root"])
    
    mkpath(cache_path)
    if args["benchmark"]
        println("Running benchmark with implementation: $(args["implementation"])")
        
        # Create symbolic link to gearshifft CMakePresets.json if it doesn't exist yet
        if !isfile(joinpath(cache_path, "CMakePresets.json"))
            symlink(joinpath(gearshifft_path, "CMakePresets.json"),
                    joinpath(cache_path, "CMakePresets.json"))
        end

        # Create corresponding CMake Preset if it doesn't exist yet
        generate_cmake_userpreset(benchmark_templates_path, args["benchmark_template"], cache_path)

        # Add benchmark logic here
    end
    
    if args["plot"]
        println("Creating plot for implementation: $(args["implementation"])")
        # Add plotting logic here
    end
end
end # module GearshifftEvaluation
