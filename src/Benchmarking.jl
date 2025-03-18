using SHA

include("../config/CustomParsers.jl") # Register custom parsers to CUSTOM_FLAG_PARSER here

# Parsing function for `parse_runtime_flags`, by default:
# <benchmark_template>[<benchmark key>] is returned as
# - a join over " " if it is an array
# - nothing if it is false
# - <benchmark_template>[<benchmark key>] else
# The default behaviour can be overridden by registering
# a function to CUSTOM_FLAG_PARSER with the key being the
# specific flag for which custom parsing behaviour is needed.
function parse(template::Dict, flag_key::Pair)
    flag, key = flag_key
    custom_parse = get(CUSTOM_FLAG_PARSER, flag, nothing)
    if !isnothing(custom_parse)
        return (flag, custom_parse(template, key))
    else
        arg = get(template, key, nothing)
        value = if isa(arg, AbstractArray)
            join(arg, " ")
        elseif isa(arg, Bool)
            arg ? arg : nothing # false should return nothing for filter
        else
            arg
        end
    end
    return (flag, value)
end

# Return a set of strings corresponding
# to the implementation binary flags and specified flag arguments
# in the benchmark values.
# In general we have in config.toml a key
#   implementations.<implementation>.run_template_variables
# ...specifying pairs:
#   <flag> = <benchmark key>
# The output for each pair is then:
#   <flag>, <benchmark_template>[<benchmark key>]
# or:
#   <flag>
# if <benchmark_template>[<benchmark key>] is just true.
# If <benchmark_template>[<benchmark key>] is false/doesn't exist,
# the flag is not added to the return vector.
function parse_runtime_flags(template::Dict, implementation::String)::Vector{String}

    # Gets flag to key map pairs for implementation (e.g ("-n", "nr_devices"))
    flags = get_template(CONFIG,
        ("implementations", implementation, "run_template_variables"))
    
    possible_template_values =
        [
            vcat(values(flags)...)...,
            vcat(values(CONFIG["build_template_variables"])...)...,
            "cmake_inherits",
            "cache_vars",
            "implementation"
        ]

    for key in keys(template)
        if !(key in possible_template_values)
            @warn "Found key '$key' in benchmark template
            which does not have an associated flag in config.toml
            (under implementations.$implementation.run_template_variables)"
        end
    end

    # map keys to the value (e.g. ("-n", 1))
    flags = map(p -> parse(template, p), collect(flags))
    # filter flag value pairs out if value is nothing (unused flags)
    flags = filter(p -> !isnothing(last(p)), flags)
    # flatten pairs to a vector of single elements
    flags = collect(Iterators.flatten(flags))
    # filter 'true' (option flags that have no argument
    # 'false' shouldn't be present at this point)
    flags = filter(e -> !isa(e, Bool), flags)
    # map remaining elements to string
    flags = map(e -> string(e), flags)

    return flags
end

function run_benchmark(template::Dict, name::String, build_hash::String, tag=nothing)
    time = "$(now())"
    template_hash = get_template_hash(template, name)
    output_dir = joinpath(OUTPUT_DIR, "csv")
    output_csv =  join([template_hash, "-", time, ".csv"])

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
    
    @info "Running benchmark with implementation '$implementation'"

    bin_path = joinpath(CACHE_DIR, build_hash)

    root_input_files_dirs = get_nested(CONFIG, ("paths", "input_file_dirs"), [])

    # Copy files from both directories to bin_path
    for dir in [INPUT_FILES_DIR, root_input_files_dirs...]
        if isdir(dir)
            for file in readdir(dir)
                src = joinpath(dir, file)
                dst = joinpath(bin_path, file)
                try
                    cp(src, dst, force = true)
                catch e
                    @warn "Failed to copy file: $file" exception=e
                end
            end
        end
    end
    
    mkpath(joinpath(CACHE_DIR, "benchmark_logs"))
    cli_vars = CONFIG["parse_cli_variables"]
    log_file = joinpath(CACHE_DIR, "benchmark_logs", "$name-$template_hash-$time.log")
    flags = parse_runtime_flags(template, implementation)

    args = [
        # implementation binary
        "./$executable",
        # runtime flags of binary
        flags...,
        # obligatory runtime flags set by ParseCli.jl
        cli_vars["benchmark_tag"],
            isnothing(tag) ? join([name, time], "@") : tag, # default tag is name and time in csv
        cli_vars["output_file"], output_csv
    ]

    command = Cmd(`sh -c $(join(args, " "))`)

    @info "Command: $command"
    run_command_from_path(command, log_file, bin_path)
    try
        mkpath(output_dir)
        cp(joinpath(bin_path, output_csv), joinpath(output_dir, output_csv), force = true)
    catch e
        @error "Failed to copy $(joinpath(bin_path, output_csv)) to $(joinpath(output_dir, output_csv))'" exception=e
        exit(1)
    end

    return template_hash
end