using CSV
using DataFrames
using Statistics

using CSV
using DataFrames

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
    meta_df = DataFrame(key=[p.key for p in kv_pairs],
                        value=[p.value for p in kv_pairs])

    # Parse main data (filter out warmup)
    df = CSV.read(IOBuffer(join(data_lines, "\n")), DataFrame; normalizenames=true)
    df = filter(r -> lowercase(string(r.run)) != "warmup", df)

    return meta_df, df
end