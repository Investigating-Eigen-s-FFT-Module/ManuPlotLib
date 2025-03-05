using TOML
using SHA

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

function get_template_hash(toml_path::AbstractString, template_name::String)
    toml_data = TOML.parsefile(toml_path)
    template = get(toml_data, template_name, nothing)
    if isnothing(template)
        error("Template '$template_name' not found in TOML file")
    end
    template_str = sprint(show, template)
    return bytes2hex(sha256(template_str))
end
