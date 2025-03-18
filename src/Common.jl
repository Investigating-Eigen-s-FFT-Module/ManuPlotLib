using TOML
using SHA

const PROJECT_ROOT = joinpath(@__DIR__, "..")
CONFIG_PATH::String = ""
CONFIG::Dict = Dict()
CONFIG_PATHS::Dict = Dict()
PLOT_TEMPLATES_PATH::String = ""
BENCHMARK_TEMPLATES_PATH::String = ""
CACHE_DIR::String = ""
BENCHMARK_ROOT::String = ""
INPUT_FILES_DIR::String = ""
OUTPUT_DIR::String = ""
CUSTOM_FLAG_PARSER = Dict()

# Load config values
function load_config(path::String)
    global CONFIG_PATH = joinpath(PROJECT_ROOT, "config", path)
    global CONFIG = TOML.parsefile(CONFIG_PATH)
    global CONFIG_PATHS = CONFIG["paths"] 
    global PLOT_TEMPLATES_PATH = joinpath(PROJECT_ROOT, "templates", CONFIG_PATHS["plot_templates_path"])
    global BENCHMARK_TEMPLATES_PATH = joinpath(PROJECT_ROOT, "templates", CONFIG_PATHS["benchmark_templates_path"])
    global CACHE_DIR = joinpath(PROJECT_ROOT, CONFIG_PATHS["cache_dir"])
    global BENCHMARK_ROOT = joinpath(PROJECT_ROOT, CONFIG_PATHS["benchmark_repo_root"])
    global INPUT_FILES_DIR = joinpath(dirname(CONFIG_PATH), "input_files")
    global OUTPUT_DIR = joinpath(PROJECT_ROOT, CONFIG_PATHS["output_dir"])
    global CUSTOM_FLAG_PARSER = CONFIG["custom_flag_parser"]
end

# Convert a string to a function name and call it
function call_function_by_name(func_name::String, args...)
    func = try
        getfield(@__MODULE__, Symbol(func_name))
    catch e
        @error "Function '$func_name' is not defined or is not a function." e
        exit(1)
    end

    try
        func(args...)
    catch e
        @error "Call to function '$func_name' failed" e
    end
end

function get_nested(toml_data::Dict, keys::Tuple, default=nothing)
    value = toml_data
    for key in keys
        value = get(value, key, default)
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
