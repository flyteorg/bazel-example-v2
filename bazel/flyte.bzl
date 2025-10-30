"""Bazel rules for running Flyte CLI commands."""

def _flyte_cli_impl(ctx):
    """Implementation of the flyte_cli rule."""

    # Create a wrapper script that runs the flyte CLI with the specified arguments
    script_content = """#!/bin/bash
set -e

# Get the flyte CLI binary
FLYTE_BIN="{flyte_bin}"

# Run flyte with the provided arguments
exec "$FLYTE_BIN" {flyte_args} "$@"
""".format(
        flyte_bin = ctx.executable._flyte_cli.short_path,
        flyte_args = " ".join(ctx.attr.flyte_args),
    )

    # Write the wrapper script
    script = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )

    # Create runfiles that include the flyte CLI and all its dependencies
    runfiles = ctx.runfiles(files = [ctx.executable._flyte_cli])
    runfiles = runfiles.merge(ctx.attr._flyte_cli[DefaultInfo].default_runfiles)

    return [
        DefaultInfo(
            executable = script,
            runfiles = runfiles,
        ),
    ]

flyte_cli = rule(
    implementation = _flyte_cli_impl,
    attrs = {
        "flyte_args": attr.string_list(
            doc = "Arguments to pass to the flyte CLI command",
            mandatory = False,
            default = [],
        ),
        "_flyte_cli": attr.label(
            default = Label("//app:_flyte_cli_bin"),
            executable = True,
            cfg = "exec",
        ),
    },
    executable = True,
    doc = """
    A rule to create executable targets that run flyte CLI commands.

    Example:
        flyte_cli(
            name = "flyte_help",
            flyte_args = ["--help"],
        )

        flyte_cli(
            name = "flyte_whoami",
            flyte_args = ["whoami"],
        )
    """,
)
