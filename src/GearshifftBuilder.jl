using TOML
using JSON3
using OrderedCollections
using SHA

get_hash(preset::OrderedDict) = bytes2hex(sha256(JSON3.write(preset)))

function generate_cmake_userpreset(toml_template_file::String, preset_name::String, cache_dir::String)
    # Check if CMakePresets.json exists in cache already
    if !isfile(joinpath(cache_dir, "CMakePresets.json"))
        error("Tried to add a CMake user preset to $cache_dir
               but CMakePresets.json from gearshifft root does not exist")
    end

    toml_data = TOML.parsefile(toml_template_file)
    
    # Get the specified preset configuration
    preset_config = get(toml_data, preset_name, nothing)
    isnothing(preset_config) && error("Benchmark preset '$preset_name' not found in TOML file")

    # Create CMake preset structure
    new_preset = 
        OrderedDict(
            "name" => preset_name,
            "displayName" => "Generated from $preset_name TOML preset",
            "inherits" => [preset_config["inherits"]],
            "cacheVariables" => OrderedDict{String, Any}(
                "GEARSHIFFT_NUMBER_WARMUPS"    => preset_config["nr_warmup"],
                "GEARSHIFFT_NUMBER_WARM_RUNS"  => preset_config["nr_warm_runs"],
                "GEARSHIFFT_ERROR_BOUND"       => preset_config["error_bound"],
                "GEARSHIFFT_DUMP_FREQUENCY"    => preset_config["dump_frequency"],
                "GEARSHIFFT_LLC_SIZE_MIB"      => preset_config["llc_mib"],
                "GEARSHIFFT_CACHE_LINE_SIZE_B" => preset_config["cl_mb"],
            )
        )
    # Merge additional cache variables if present
    if haskey(preset_config, "cache_vars")
        merge!(new_preset["cacheVariables"], 
                preset_config["cache_vars"])
    end
    
    # Add hash key as comment for unique id
    push!(new_preset, "\$comment" => get_hash(new_preset))
    
    # Convert all cache variables to String
    for (key, value) in new_preset["cacheVariables"]
        new_preset["cacheVariables"][key] = string(value)
    end
    
    # Write to CMakeUserPresets.json
    output_path = joinpath(cache_dir, "CMakeUserPresets.json")

    # Initialize or load existing CMakeUserPresets.json
    cmake_presets = if isfile(output_path)
        # Load existing presets
        existing_presets = JSON3.read(read(output_path, String), OrderedDict{String, Any})
        
        # Check if this preset already exists
        if haskey(existing_presets, "configurePresets")
            preset_idx = findfirst(p -> p["name"] == preset_name, existing_presets["configurePresets"])
            if !isnothing(preset_idx)
                existing_preset = existing_presets["configurePresets"][preset_idx]
                if existing_preset["\$comment"] != new_preset["\$comment"] # comment contains SHA
                    @info "Preset '$preset_name' already exists in cached CMakeUserPresets.json. Overwriting."
                    existing_presets["configurePresets"][preset_idx] = new_preset
                else
                    return # nothing new to write
                end
            else
                push!(existing_presets["configurePresets"], new_preset)
            end
        else
            existing_presets["configurePresets"] = [new_preset]
        end

        existing_presets
    else
        @info "No CMakeUserPresets.json in cache, creating new one..."
        OrderedDict(
            "\$schema" => "https://raw.githubusercontent.com/Kitware/CMake/refs/tags/v3.31.5/Help/manual/presets/schema.json",
            "version" => 10,
            "cmakeMinimumRequired" => OrderedDict(
                "major" => 3,
                "minor" => 31,
                "patch" => 0
            ),
            "configurePresets" => [new_preset]
        )
    end

    # Write updated presets to file (if cmake_presets isn't nothing)
    open(output_path, "w") do io
        JSON3.pretty(io, cmake_presets)
    end
end