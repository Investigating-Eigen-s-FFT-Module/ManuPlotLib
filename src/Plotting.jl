using PGFPlotsX
using ColorSchemes
using JSON3

escape_latex_special_chars(str::String) = replace(str, r"([%$#&_{}~^\\])" => s"\\\1")

function create_plot(template::Dict{String,Any}, template_name::String,
                     output_dir::AbstractString, benchmark_templates::Dict{String,Any})
    @info "Creating plot with plot template '$template_name'"
    plot_hash = get_template_hash(template, template_name)
    td = TikzDocument()

    benchmark_template_names = template["benchmark_templates"]

    @info "Searching for benchmark template csv files for:\n$(join(benchmark_template_names, "\n"))"
    get_template_v = name -> get_template(benchmark_templates, name)
    benchmark_template_hashes = get_template_hash.(
        get_template_v.(benchmark_template_names), benchmark_template_names
    )
    if length(benchmark_template_hashes) == 0
        @error "Could not find benchmark data for benchmark templates:" template["benchmark_templates"]
        exit(1)
    end
    @info "Found suitable csv files with hashes:\n$(join(benchmark_template_hashes, "\n"))"

    aggregate = df -> aggregate_data(template, df)

    agg_data_list = []
    meta_data_list = []
    metadata = Dict(("plot_template" => Dict("name" => template_name, "hash" => plot_hash)),
        "benchmark_templates" => [])
    
    @info "Gathering and aggregating csv files..."
    for (name, hash) in zip(benchmark_template_names, benchmark_template_hashes)
        md, d = try
            gather_data(template, output_dir, hash)
        catch e
            @error "Data gather failed for benchmark template '$name'" e
            exit(1)
        end
        
        @info "Gathered $(template["combine_same_benchmark_data"] ? "and combined " : "")
    $(length(md)) csv files for benchmark template '$name'"

        try
            push!(agg_data_list, aggregate.(d))
            push!(meta_data_list, md)
            push!(metadata["benchmark_templates"],
                Dict(
                    "name" => name,
                    "hash" => hash,
                    "csv_meta_data" => md
                    )
                )
        catch e
            @error "Data aggregation failed for benchmark template '$name'" e
            exit(1)
        end
        @info "Aggregated data for benchmark template '$name'"
    end
    
    # SUBPLOTS CREATION
    group_cols = template["group_by_columns"]
    xcol = template["x_values"][1]
    ycols = template["y_values"]

    color_map = ColorSchemes.glasbey_hv_n256.colors
    push_preamble!(td, ("glasbeyhvn256", color_map))
    
    # Create a list to hold each subplot's axis
    axes = []
    meta_data_labels = template["meta_data_labels"]

    for ycol in ycols
        @info "Creating subplot for y column: $ycol"
        
        # Each df_vec should correspond to a benchmark hash
        # md_vec contains the corresponding set of csv metadata info from the csv(s)
        
        # First determine unique identifiers based on group column names to build legend labels
        # and titles
        group_col_entries = DataFrame([name => [] for name in  group_cols])
        for df_vec in agg_data_list 
            for df in df_vec
                append!(group_col_entries, unique(eachrow(df[:, group_cols])))
            end
        end
        
        # Determine columns with different entries
        different_entry_cols = [] # entries will be in label
        
        for (col_name, col) in zip(names(group_col_entries), eachcol(group_col_entries))
            unique_entries = unique(col)
            if length(unique_entries) != 1
                push!(different_entry_cols, col_name)
            end
        end
        @info "Identifying column entries for subplot are:\n$(join(different_entry_cols, "\n"))"

        # Create a new axis for each y column
        ycol_axis = @pgf Axis(
            {
                raw"axis background/.style={fill=gray!10}",
                title = escape_latex_special_chars(ycol * "_" * template["aggregation_function"]),
                xmode = template["x_scale"],
                ymode = template["y_scale"],
                log_basis_x = template["x_log_basis"],
                log_basis_y = template["y_log_basis"],
                x_dir = template["x_dir"],
                y_dir = template["y_dir"],
                y_label_style = {at={"(yticklabel* cs:1)"}, anchor="north west",
                    rotate=-90, yshift="1em", xshift="-4em"},
                grid = "both",
                grid_style = "white",
                legend_pos = "outer north east",
                legend_cell_align = "left",
                colormap_name = "glasbeyhvn256",
                cycle_multiindex_list = "[of colormap]\\nextlist mark list"
            }
        )

        if template["error_bar_method"] != "none"
            push!(ycol_axis.options,
                "error bars/y dir=both",
                "error bars/y explicit"
            )
        end

        # Run through dfs again and create curves
        for (df_vec, md_vec) in zip(agg_data_list, meta_data_list)
            for (df, md) in zip(df_vec, md_vec)
                grouped_df = groupby(df, group_cols)
                for gdf in grouped_df
                    x_data = gdf[:, xcol]
                    y_data = gdf[:, ycol]
                    
                    label_cols = [string(gdf[1, col]) for col in different_entry_cols]
                    group_label = string(join(label_cols, ", "))
                    @info "Adding series '$group_label' to subplot"
                    
                    try
                        for key in meta_data_labels
                            @info "Adding metadata '$key' to series label"
                            group_label *= ", $(md[key])"
                        end
                        
                        plot = if template["error_bar_method"] != "none"
                            y_err = gdf[:, ycol * "_" * template["error_bar_method"]]

                            @pgf Plot(
                                Coordinates(x_data, y_data; yerror = y_err)
                            )
                        else
                            @pgf Plot(
                                Table(x_data, y_data)
                            )
                        end

                        # Add to axis for this y value
                        push!(ycol_axis, plot)
                        push!(ycol_axis, LegendEntry(escape_latex_special_chars(group_label)))
                    catch e
                        @error "Series creation failed:" e
                        exit(1)
                    end
                end
            end
        end
        @info "Subplot for y column '$ycol' done!"
        push!(axes, ycol_axis)
    end
    
    @info "Combining subplots to final plot"
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
                xlabel = escape_latex_special_chars(template["x_label"]),
                ylabel = escape_latex_special_chars(template["y_label"])
            }
        )

        for axis in axes
            push!(groupplot, axis)
        end
        
        push!(td, TikzPicture(groupplot))
    else
        # For a single plot
        single_axis = axes[1]
        push!(single_axis.options,
            :xlabel => escape_latex_special_chars(template["x_label"]),
            :ylabel => escape_latex_special_chars(template["y_label"])
        )
        push!(td, TikzPicture(single_axis))
    end
    
    datetime = string(now())
    save_path = joinpath(output_dir, template_name, plot_hash, datetime)
    @info "Saving output files at:
    '$save_path'"
    mkpath(save_path)
    # Save the figure
    pgfsave(joinpath(save_path, "$template_name.tex"), td)
    pgfsave(joinpath(save_path, "$template_name.pdf"), td)

    # Save the metadata to a JSON file
    open(joinpath(save_path, "metadata_$(template_name).json"), "w") do io
        JSON3.pretty(io, metadata)
    end
    @info "Plotting completed successfully" datetime
end