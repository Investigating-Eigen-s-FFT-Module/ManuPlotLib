using TOML
using SHA

function run_benchmark(fft_implementation::Symbol, build_hash::String, benchmark_template::String,
                       gearshifft_root::AbstractString, cache_dir::AbstractString,
                       benchmark_templates_dir::AbstractString, output_dir::AbstractString)
    # get benchmark template arguments
    time = "$(now())"
    toml_data = TOML.parsefile(benchmark_templates_dir)
    template = get_template(toml_data, benchmark_template)
    @show template
    template_hash = get_template_hash(benchmark_templates_dir, benchmark_template)
    output_csv =  join([template_hash, "-" , time, ".csv"])

    extents::AbstractArray = template["extents"]
    (length(extents) == 0) && error("Benchmark template '$benchmark_template' doesn't have any extents files specified")

    verbose::Bool          = template["verbose"]
    nr_devices::Integer    = template["nr_devices"]

    bin_path = joinpath(cache_dir, build_hash)
    executable = "gearshifft_$(fft_implementation)"

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
    log_file = joinpath(cache_dir, "benchmark_logs", "$(template_hash)-$time.log")
    base_args = [
        "./$executable",
        "-f", join(extents, " "),
        "-o", output_csv,
        "-t", time,
        verbose ? "-v" : nothing,
        "-n", "$nr_devices"
    ]
    filtered_args = Vector{String}(filter(x -> x !== nothing, base_args))
    command = Cmd(filtered_args)

    @info "Running benchmark: $command"
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