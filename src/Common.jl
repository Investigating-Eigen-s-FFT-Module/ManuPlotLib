using TOML
using SHA

# Load default config values
function load_config()::Dict
    config_path = joinpath(@__DIR__, "..", "config", "config.toml")
    return TOML.parsefile(config_path)
end

const CONFIG = load_config()

function get_nested(toml_data::Dict, keys::Tuple, default=nothing)
    value = toml_data
    for key in keys
        value = get(value, key, nothing)
    end
    return value
end

function get_template(toml_data::Dict, name::String, visited::AbstractArray=[])
    # Get the specified preset configuration
    template = get(toml_data, name, nothing)
    isnothing(template) && error("Key: '$name' not found in TOML file")

    # Check for parents
    parent = get(template, "inherits", nothing)
    parent_template = if !isnothing(parent)
        (parent in visited) && error("Key: '$name' detected circular inheritance")
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
    delete!(template, "inherits") # remove inheritance key, final merged template shouldn't have it anymore
    
    return template
end

# Nested version will check for parents across all levels of nestedness - NOT TESTED ON SPECIAL
# cmake_inherits AND cache_vars BEHAVIOUR
function get_template(toml_data::Dict, names::Tuple{Vararg{String}}, visited::AbstractArray=[])
    # Get the specified preset configuration
    template = get_nested(toml_data, names)
    isnothing(template) && return nothing

    # Check for parents
    parent = get(template, "inherits", nothing)
    parent_templates = []
    if !isnothing(parent)
        (parent in visited) && error("Key: '$(join(names, "."))' detected circular inheritance")
        push!(visited, join(names, "."))

        for i in 0:length(names)-1
            parent_template = get_template(toml_data, (names[1:i]..., parent), visited)
            if !isnothing(parent_template)
                push!(parent_templates, parent_template)
            end
        end

        if isempty(parent_templates)
            @error "Could not find key: '$parent' which is inherited by '$names[1]'"
            exit(1)
        end

        delete!(template, "inherits") # remove inheritance key, final merged template shouldn't have it anymore
    end

    if length(parent_templates) > 1
        @warn "Found multiple keys for key: '$parent' which is inherited by  '$names[1]'.
    Inheritance will default to highest level one"
    end

    if !isempty(parent_templates) # Merge and overwrite parent template
        parent_template = parent_templates[1] # default to highest level one found
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
