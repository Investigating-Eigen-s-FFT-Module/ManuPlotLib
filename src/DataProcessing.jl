using CSV
using DataFrames
using Dates
using Statistics

function aggregate_data(template::Dict{String,Any}, data::DataFrame,
                        gb_columns::AbstractArray, columns::AbstractArray)
    agg_fun = try
        Dict(
            "mean" => mean,
            "median" => median,
            "min" => minimum,
            "max" => maximum
        )[template["aggregation_function"]]
    catch e
        @error "Invalid aggregation function: '$(template["aggregation_function"])'" e
        exit(1)
    end

    error_method = try
        Dict(
            "std_dev" => std,
            "quantiles" => quantile,
            "max_dev" => x -> maximum(abs.(x - mean(x))),
            "none" => nothing
        )[template["error_bar_method"]]
    catch e
        @error "Invalid error bar method: '$(template["error_bar_method"])'" e
        exit(1)
    end

    grouped_df = groupby(data, gb_columns)
    
    transformations = []
    for col in columns

        push!(transformations, col => agg_fun => col * "_" * template["aggregation_function"])

        if !isnothing(error_method)
            push!(transformations, col => error_method => col * "_" * template["error_bar_method"])
        end
    end
    agg_results = combine(grouped_df, transformations...)

    return agg_results
end

function gather_data(template::Dict{String,Any}, output_dir::AbstractString, run_hash::String, tag=nothing)
    data_dir = joinpath(output_dir, "csv")
    # Gather all CSV files matching our run_hash-<datetime>.csv pattern
    all_files = readdir(data_dir)

    # Parse and sort by datetime descending
    parsed_files = []
    for f in all_files
        m = match(r"^" * run_hash * r"-(.*)\.csv$", f)
        if !isnothing(m)
            # Attempt to parse the datetime portion
            dtstr = m.captures[1]
            dt = try
                DateTime(dtstr, dateformat"yyyy-mm-ddTHH:MM:SS.sss")
            catch e
                @error "Failed to read datetime in filename of a csv in $data_dir"
                showerror(stdout, e)
                exit(1)
            end
            push!(parsed_files, (file=f, dt=dt))
        end
    end
    sort!(parsed_files, by = x -> x.dt, rev=true)  # most recent first
    
    if isempty(parsed_files)
        throw(ArgumentError("Found no matching benchmark csv's for hash: '$run_hash'"))
    end

    meta_list = []
    data_list = []
    for pf in parsed_files
        meta_data, data = read_gearshifft_results_csv(joinpath(data_dir, pf.file))
        if !isnothing(tag)
            if ismatch(Regex(tag), meta_data["tag"])
                push!(meta_list, meta_data)
                push!(data_list, data)
            else
                @info "Skipping a benchmark output csv due to mismatched csv tag:
                '$(meta_df[:tag])' doesn't match '$tag'"
            end
        else
            push!(meta_list, meta_data)
            push!(data_list, data)
        end
    end
    num_files = template["csv_count_per_benchmark"] <= 0 ? length(meta_list) : template["csv_count_per_benchmark"]
    meta_list = first(meta_list, min(num_files, length(meta_list)))
    data_list = first(data_list, min(num_files, length(data_list)))

    if template["combine_same_benchmark_data"]
        return ([meta_list], [reduce(vcat, data_list)])
    else
        return (meta_list, data_list)
    end
end

function read_gearshifft_results_csv(filename::String)
    lines = readlines(filename)
    # Separate commented (meta) lines from data lines
    meta_lines = filter(line -> startswith(strip(line), ";"), lines)
    data_lines = filter(line -> !startswith(strip(line), ";"), lines)

    # Convert meta lines to key-value pairs
    kv_pairs = []
    for line in meta_lines
        line = replace(line, r"^;\s?" => "")
        # Split on commas, remove quotes/extra spaces
        parts = split(line, ",")
        parts = [strip(replace(p, "\"" => "")) for p in parts if !isempty(strip(replace(p, "\"" => "")))]
        # Store as (key, value) pairs
        i = 1
        while i < length(parts)
            push!(kv_pairs, (key=parts[i], value=parts[i+1]))
            i += 2
        end
    end
    meta_info = Dict(kv_pairs)

    # Parse main data (filter out warmup)
    data = CSV.read(IOBuffer(join(data_lines, "\n")), DataFrame; normalizenames=true)
    rename!(data, Dict(col => Symbol(rstrip(string(col), '_')) for col in names(data)))
    filter!(data) do row
        row.success != "Warmup"
    end

    if any(row -> row.success != "Success", eachrow(data))
        @warn "Found failed run in dataset: '$filename'"
    end

    return meta_info, data
end