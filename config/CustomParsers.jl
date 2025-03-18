# Here custom parsers can be added to parse arguments of benchmark templates for specific flags
# if needed. The function signature for a custom parser is:
#   function (template::Dict, val::Any)::String
# - template is the benchmark template loaded from the TOML file
# - val is the benchmark template keys associated with the flag
# It should return a string specifiying the argument for the flag.
# Each custom parser can be registered to flags in CUSTOM_FLAG_PARSER
# Note: for implementation-specific parsing, simply get the implementation
#       from the template (template["implementation"])

function gearshifft_benchmark_string(template::Dict, val::AbstractArray{String})
    # translate following params to wildcard syntax
    benchmarks_string = try
        inplace::Bool          = template[val[1]] # inplace
        outplace::Bool         = template[val[2]] # outplace
        real::Bool             = template[val[3]] # real
        complex::Bool          = template[val[4]] # complex
        precision::String      = template[val[5]] # precision
        
        benchmarks_string = "*/"
        benchmarks_string *= (precision == "all" ? "*/*/" : "$precision/*/") # second '*' is extent, which is not specified
        benchmarks_string *= (inplace && outplace ? "*_" : (inplace ? "Inplace_" : "Outplace_"))
        benchmarks_string *= (real && complex ? "*" : (real ? "Real" : "Complex"))
        
        if !(inplace || outplace)
            throw(ArgumentError("Both inplace and outplace benchmarks set to false in benchmark template '$name'"))
        elseif !(real || complex)
            throw(ArgumentError("Both real and complex benchmarks set to false in benchmark template '$name'"))
        end
        
        "\"" * benchmarks_string * "\""
    catch e
        @error "Failed to parse runtime benchmarks string" e
        exit(1)
    end
end

const CUSTOM_FLAG_PARSER = Dict(
    "-r" => gearshifft_benchmark_string
)