using Plots

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
        push!(meta_data_list, Dict("benchmark_template" => name, "csv_meta_data" => md))
    end

    p = plot()
    for (df_vec, md_vec) in zip(agg_data_list, meta_data_list)
        for (df, md) in zip(df_vec, md_vec)
            create_plot_series(template, df, p)
        end
    end
end


function create_plot_series(template::Dict, df::DataFrame, p)
    scales = (xscaling = template["x_scale"], yscaling = template["y_scale"])
    get_scale_symbol(x::String) = x in ["log10", "log2", "identity"] ? Symbol(x) : :identity

    xcol = template["x_values"][1]
    ycols = template["y_values"]

    y_transform = template["y_transform"] == "none" ? (x, y) -> y :
                  template["y_transform"] == "flops_per_ms" ? (x, y) -> x * log2(x) / y :
                  (x, y) -> y

    x_transform = template["x_transform"] == "none" ? x -> x :
                  template["x_transform"] == "B_to_MiB" ? x -> x * 2e-10 :
                  x -> x
  
    group_cols = template["group_by_columns"]
    grouped_df = groupby(df, group_cols)
    
    plot!(p, # TODO formatting
          xaxis =:log2, # todo: fix scaling
          yaxis =:log10,
          size=(2000, 1000),
          legendfontsize=12,
          legend=:outerright
    )
    for (i, ycol) in enumerate(ycols)
        for gdf in grouped_df
            x_data = x_transform.(gdf[:, xcol])
            y_data = y_transform.(x_data, gdf[:, ycol])
            group_label = join([string(gdf[1, col]) for col in group_cols], ", ")
            scatter!(p, x_data, y_data, label=group_label)
        end
    end
    savefig(p, string("test.svg"))
end