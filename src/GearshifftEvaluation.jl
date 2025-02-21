module GearshifftEvaluation

include("Benchmarking.jl")
include("DataProcessing.jl")
include("GearshifftBuilder.jl")
include("ParseCli.jl")
include("Plotting.jl")

function main()
    args = parse_commandline()

    if args["benchmark"]
        println("Running benchmark with implementation: $(args["implementation"])")
        # Add benchmark logic here
    end
    
    if args["plot"]
        println("Creating plot for implementation: $(args["implementation"])")
        # Add plotting logic here
    end
end
end # module GearshifftEvaluation
