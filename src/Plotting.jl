using Plots

markers = [:circle :square :diamond :utriangle :dtriangle :pentagon :hexagon :star4 :star5 :cross] # todo, extend

function create_plot(template::Dict{String,Any}, output_dir::AbstractString, benchmark_templates::Dict{String,Any})

    group_by_names = vcat(template["x_values"], template["group_by_columns"])
    benchmark_template_names = template["benchmark_templates"]

    get_template_v = name -> get_template(benchmark_templates, name)
    benchmark_template_hashes = get_template_hash.(
        get_template_v.(benchmark_template_names), benchmark_template_names
    )
    if length(benchmark_template_hashes) == 0
        @error "Could not find benchmark data for benchmark templates:" template["benchmark_templates"]
        exit(1)
    end

    aggregate = df -> aggregate_data(template, df, group_by_names, template["y_values"])

    agg_data_list = []
    meta_data_list = []
    
    for (name, hash) in zip(benchmark_template_names, benchmark_template_hashes)
        md, d = try
            gather_data(template, output_dir, hash)
        catch e
            @error "Data gather failed for benchmark template '$name'" e
            exit()
        end
        
        push!(agg_data_list, aggregate.(d))
        push!(meta_data_list, md)
    end
    p = plot()
    # each df_vec should correspond to a benchmark hash
    # md_vec contains the corresponding set of csv metadata info from the csv(s)
    for (df_vec, md_vec) in zip(agg_data_list, meta_data_list)
        for (df, md) in zip(df_vec, md_vec)
            create_plot_series(template, df, md, p)
        end
    end
end


function create_plot_series(template::Dict, df::DataFrame, metadata::Dict, p)
    scales = (xscaling = template["x_scale"], yscaling = template["y_scale"])
    get_scale_symbol(x::String) = x in ["log10", "log2", "identity"] ? Symbol(x) : :identity

    xcol = template["x_values"][1]
    ycols = template["y_values"] .* ("_" * template["aggregation_function"])

    y_transform = template["y_transform"] == "none" ? (x, y) -> y :
                  template["y_transform"] == "flops_per_ms" ? (x, y) -> x * log2(x) / y :
                  (x, y) -> y

    x_transform = template["x_transform"] == "none" ? x -> x :
                  template["x_transform"] == "B_to_MiB" ? x -> x * 2e-10 :
                  x -> x
  
    group_cols = template["group_by_columns"]
    grouped_df = groupby(df, group_cols)
    
    plot!(
        p,
        xaxis = get_scale_symbol(scales.xscaling),
        yaxis = get_scale_symbol(scales.yscaling),
        legend=:outerright,
        background_color=:gray,
        gridcolor=:white,
        palette=:Pastel1,
        xticks=:all,              # x ticks at each x value
        yticks=:auto              # automatically choose more granular y ticks
    )

    # Identify columns that vary across the entire DataFrame
    unique_vals = Dict()
    for col in group_cols
        unique_vals[col] = unique(df[!, col])
    end
    varying_cols = [col for col in group_cols if length(unique_vals[col]) > 1]

    for ycol in ycols
        for gdf in grouped_df
            sort!(gdf, xcol) # sorting for line plots
            x_data = x_transform.(gdf[:, xcol])
            y_data = y_transform.(x_data, gdf[:, ycol])
    
            # Build label only from columns that vary plus the ycol
            label_cols = [string(gdf[1, col]) for col in varying_cols]
            group_label = length(label_cols) > 0 ?
                string(join(label_cols, ", "), " (", ycol, ")") :
                ycol
            
            # If we compare the same benchmark template, use the csv tags to differentiate
            if !template["combine_same_benchmark_data"]
                group_label *= " - $(metadata["tag"])"
            end
    
            plot!(p, x_data, y_data, label=group_label)
        end
    end
    savefig(p, string("test.svg"))
end