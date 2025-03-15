using SHA

# Base function which takes 
function parse_runtime_flag(template::Dict, key::String)
    arg = get(template, key, nothing)

    if isa(arg, AbstractArray)
        join(arg, " ")
    elseif isa(arg, Bool)
        arg ? arg : nothing
    else
        arg
    end
end

function run_benchmark(template::Dict, name::String, build_hash::String,
                       gearshifft_root::AbstractString, cache_dir::AbstractString,
                       output_dir::AbstractString, tag=nothing)
    time = "$(now())"
    template_hash = get_template_hash(template, name)
    output_csv =  join([template_hash, "-" , time, ".csv"])

    implementation = get(template, "implementation", nothing)
    if isnothing(implementation)
        @error "Benchmark template '$name' does not specify an FFT implementation"
        exit(1)
    end
    if !(implementation in keys(CONFIG["implementations"]))
        @error "Specified implementation '$implementation' not found in config/config.toml"
        exit(1)
    end

    executable = get_nested(CONFIG, ("implementations", implementation, "binary"))
    runtime_flags = get_template(CONFIG,
        ("implementations", implementation, "run_template_variables"))
    
    @info "Running benchmark with implementation '$implementation'"

    extents::AbstractArray = template["extents"]
    (length(extents) == 0) && error("Benchmark template '$name' doesn't have any extents files specified")

    # translate following params to wildcard syntax
    benchmarks_string = try
        inplace::Bool          = template["inplace"]
        outplace::Bool         = template["outplace"]
        real::Bool             = template["real"]
        complex::Bool          = template["complex"]
        precision::String      = template["precision"]

        benchmarks_string = "*/"
        benchmarks_string *= (precision == "all" ? "*/*/" : "$precision/*/") # second '*' is extent, which is not specified
        benchmarks_string *= (inplace && outplace ? "*_" : (inplace ? "Inplace_" : "Outplace_"))
        benchmarks_string *= (real && complex ? "*" : (real ? "Real" : "Complex"))

        if !(inplace || outplace)
            throw(ArgumentError("Both inplace and outplace benchmarks set to false in benchmark template '$name'"))
        elseif !(real || complex)
            throw(ArgumentError("Both real and complex benchmarks set to false in benchmark template '$name'"))
        end

        benchmarks_string
    catch e
        @error "Failed to parse runtime benchmarks string"
        showerror(stdout, e)
        exit(1)
    end 
    bin_path = joinpath(cache_dir, build_hash)

    extents_dir = joinpath(@__DIR__, "..", "config", "extents")
    gearshifft_extents_dir = joinpath(gearshifft_root, "share", "gearshifft")
    # Copy extent files from both directories to bin_path
    for dir in [extents_dir, gearshifft_extents_dir]
        if isdir(dir)
            for file in readdir(dir)
                src = joinpath(dir, file)
                dst = joinpath(bin_path, file)
                try
                    cp(src, dst, force = true)
                catch e
                    @warn "Failed to copy extent file: $file" exception=e
                end
            end
        end
    end
    
    mkpath(joinpath(cache_dir, "benchmark_logs"))
    cli_vars = CONFIG["parse_cli_variables"]
    log_file = joinpath(cache_dir, "benchmark_logs", "$name-$template_hash-$time.log")
    
    # Gets flag to key map pairs (e.g ("-n", "nr_devices")),
    # maps it to the runtime arg (e.g. ("-n", 1), filters them out
    # if value is false or nothing (unused flags) and flattens
    # them to a string
    flags = map(p -> (first(p), parse_runtime_flag(template, last(p))), collect(runtime_flags))
    flags = filter(p -> !isnothing(last(p)), flags)
    flags = collect(Iterators.flatten(flags))
    flags = map(e -> string(e), flags)

    args = [
        # implementation binary
        "./$executable",
        # runtime flags of binary
        flags...,
        "-r", benchmarks_string,
        # obligatory runtime flags set by ParseCli.jl
        cli_vars["benchmark_tag"],
            isnothing(tag) ? join([name, time], "@") : tag, # default tag is name and time in csv
        cli_vars["output_file"], output_csv
    ]

    command = Cmd(args)

    @info "Comand: $command"
    run_command_from_path(command, log_file, bin_path)
    try
        mkpath(joinpath(output_dir, "csv", output_csv))
        cp(joinpath(bin_path, output_csv), joinpath(output_dir, "csv", output_csv), force = true)
    catch e
        @error "Failed to retrieve $(joinpath(bin_path, output_csv)) to $(joinpath(output_dir, output_csv))'" exception=e
        exit(1)
    end

    return template_hash
end