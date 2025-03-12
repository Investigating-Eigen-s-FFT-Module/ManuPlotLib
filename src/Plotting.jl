using PGFPlotsX
using ColorSchemes

escape_latex_special_chars(str::String) = replace(str, r"([%$#&_{}~^\\])" => s"\\\1")

function create_plot(template::Dict{String,Any}, output_dir::AbstractString, benchmark_templates::Dict{String,Any})
    td = TikzDocument()

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
    
    # SUBPLOTS CREATION
    group_cols = template["group_by_columns"]
    xcol = template["x_values"][1]
    ycols = template["y_values"] .* ("_" * template["aggregation_function"])

    color_map = first(ColorSchemes.glasbey_hv_n256.colors, length(ycols))
    push_preamble!(td, ("glasbeyhvn256", color_map))
    
    y_transform = template["y_transform"] == "none" ? (x, y) -> y :
    template["y_transform"] == "flops_per_ms" ? (x, y) -> 5. * x * log2(x) / y :
    (x, y) -> y
    x_transform = template["x_transform"] == "none" ? x -> x :
    template["x_transform"] == "B_to_MiB" ? x -> x * 2e-10 :
    x -> x
    
    # Create a list to hold each subplot's axis
    axes = []

    for ycol in ycols
        # Create a new axis for each y column
        ycol_axis = @pgf Axis(
            {
                raw"axis background/.style={fill=gray!10}",
                title = escape_latex_special_chars(ycol),
                xmode = template["x_scale"],
                ymode = template["y_scale"],
                log_basis_x = template["x_log_basis"],
                log_basis_y = template["y_log_basis"],
                x_dir = template["x_dir"],
                y_dir = template["y_dir"],
                y_label_style = {at={"(yticklabel* cs:1)"}, anchor="north west", rotate=-90, yshift="1.5em", xshift="-4em"},
                grid = "major",
                grid_style = "white",
                legend_pos = "outer north east",
                legend_style = {align="left"},
                colormap_name = "glasbeyhvn256",
                cycle_multiindex_list = "[of colormap]\\nextlist mark list"
            }
        )
        
        # Each df_vec should correspond to a benchmark hash
        # md_vec contains the corresponding set of csv metadata info from the csv(s)
        for (df_vec, md_vec) in zip(agg_data_list, meta_data_list)
            for (df, md) in zip(df_vec, md_vec)
                # TODO: FIX varying cols: if defined here, it won't receive different implementation
                unique_vals = Dict(col => unique(df[!, col]) for col in group_cols)
                varying_cols = [col for col in group_cols if length(unique_vals[col]) > 1]
                
                grouped_df = groupby(df, group_cols)
            
                for gdf in grouped_df
                    sort!(gdf, xcol)
                    x_data = x_transform.(gdf[:, xcol])
                    y_data = y_transform.(x_data, gdf[:, ycol])
                    
                    label_cols = [string(gdf[1, col]) for col in varying_cols]
                    group_label = length(label_cols) > 0 ? string(join(label_cols, ", ")) : ""

                    if !template["combine_same_benchmark_data"] || group_label == ""
                        group_label *= md["tag"]
                    end
                    
                    plot = @pgf Plot(
                        Table(x_data, y_data)
                    )

                    # Add to axis for this y value
                    push!(ycol_axis, plot)
                    push!(ycol_axis, LegendEntry(escape_latex_special_chars(group_label)))
                end
            end
        end
        
        push!(axes, ycol_axis)
    end
    
    # Create the final figure with all subplots
    if length(axes) > 1
        # For multiple plots, use a groupplot
        groupplot = @pgf GroupPlot(
            {
                group_style = {
                    group_size = "1 by $(length(axes))",
                    vertical_sep = "1cm",
                    horizontal_sep = "1cm",
                    x_descriptions_at = "edge bottom"
                },
                xlabel = escape_latex_special_chars(xcol),
                ylabel = "TODO"
            }
        )

        for axis in axes
            push!(groupplot, axis)
        end
        
        push!(td, TikzPicture(groupplot))
    else
        # For a single plot
        push!(td, TikzPicture(axes[1]))
    end
    
    # Save the figure
    pgfsave(joinpath(output_dir, "test.tex"), td)
    pgfsave(joinpath(output_dir, "test.pdf"), td)
end