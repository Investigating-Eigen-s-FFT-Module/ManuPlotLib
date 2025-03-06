using Plots

function create_plot(
    template::Dict{String,Any},
    data::Dict{Symbol, Vector{Float64}},
    plt::Plots.Plot = nothing
)
    # Create a new plot object if none is provided
    plt = plt === nothing ? plot() : plt

    # Apply any y-axis transform if specified
    x = data[:x]
    transformed_y = copy(data[:y])
    if template["y_transform"] != "none"
        if template["y_transform"] == "flops_per_ms"
            # TODO figure out a better count for flops for FFT
            transformed_y .= x .* log2.(x) ./ transformed_y
        end
    end

    # Set scale arguments for Plots
    scales = (xscaling = template["x_scale"], yscaling = template["y_scale"])

    # Add a new series to the plot
    plot!(
        x, transformed_y,
        xlabel = template["x_label"],
        ylabel = template["y_label"],
        xscale = scales.xscaling,
        yscale = scales.yscaling,
    )
    
    return plt
end