using TOML
using SHA

function get_template(toml_data::Dict, name::String, visited::AbstractArray=[])
    # Get the specified preset configuration
    template = get(toml_data, name, nothing)
    isnothing(template) && error("Benchmark template '$name' not found in TOML file")

    # Check for parents
    parent = get(template, "inherits", nothing)
    parent_template = if !isnothing(parent)
        (parent in visited) && error("Benchmark template '$name' detected circular inheritance")
        push!(visited, name)
        get_template(toml_data, parent, visited)
    end

    if !isnothing(parent_template) # Merge and overwrite with parent preset
        template = merge(parent_template, template)
        if haskey(parent_template, "cmake_inherits") && haskey(template, "cmake_inherits") # handle merging of cmake inherits
            template["cmake_inherits"] =
                vcat(template["cmake_inherits"], setdiff(parent_template["cmake_inherits"], template["cmake_inherits"])) # append older parent's cmake inherits if
                                                                                                                         # they don't exist yet
        end
        if haskey(parent_template, "cache_vars") && haskey(template, "cache_vars") # handle merging of additional cache variables
            merge!(parent_template["cache_vars"], template["cache_vars"])
        end
    end
    return template
end

function run_command_from_path(command::Cmd, log_file::AbstractString, path::AbstractString)
    mkpath(dirname(log_file))
    open(log_file, "w") do log
        try
            proc = run(pipeline(
                Cmd(command, dir=path),
                stdout=log,
                stderr=log
            ))
            status = proc.exitcode  # Get the actual exit code
            if status != 0
                @error "'$command' failed, exit code $status. Check $log_file for details."
                exit(1)
            end
        catch e
            @error "Failed to run '$command'. Check $log_file for details." exception=e
            exit(1)
        end
    end
end

function get_template_hash(template::Dict, name::String)
    template_str = sprint(show, template)
    return bytes2hex(
        sha256(
            join([template_str, name])
        )
    )
end
