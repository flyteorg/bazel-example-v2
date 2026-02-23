"""Bazel rules for running Flyte CLI commands and Python API functions."""

load("@aspect_rules_py//py:defs.bzl", "py_binary")

def _make_flyte_target(name, src_file, args, deps, kwargs):
    """Creates a one-line wrapper + py_binary that dispatches to flyte_runner.

    Each target gets a tiny generated main script that imports and calls the
    shared flyte_runner.main().  All per-target config is passed via CLI args
    (the py_binary `args` attribute), so zero application logic is generated.

    Args:
        name: Target name for the py_binary
        src_file: User's Python source file (task or env module)
        args: CLI arguments forwarded to flyte_runner
        deps: Dependencies for the py_binary
        kwargs: Extra kwargs forwarded to py_binary
    """
    script_name = name + "_main.py"
    native.genrule(
        name = name + "_gen",
        outs = [script_name],
        cmd = "echo 'from flyte_runner import main; main()' > $@",
    )
    py_binary(
        name = name,
        srcs = [script_name, src_file],
        main = script_name,
        args = args,
        deps = deps + ["//bazel:_flyte_runner_lib"],
        imports = ["."],
        **kwargs
    )

def flyte_run(name, task_file, task_function, mode = "local", params = [], config_file = None, log_level = 30, deps = [], **kwargs):
    """
    A macro to create a py_binary target that runs Flyte tasks locally or remotely using flyte.run().

    Args:
        name: Name of the target
        task_file: The Python file containing the Flyte task
        task_function: The name of the task function to run
        mode: Execution mode: 'local' or 'remote' (default: 'local')
        params: Parameters to pass to the task (format: key=value)
        config_file: Path to Flyte config file (used for remote mode). If None, uses flyte.init_from_config() to auto-discover .flyte/config.yaml
        log_level: Logging level (int), default 30 (WARNING). Set to 10 for DEBUG.
        deps: Dependencies required by the task
        **kwargs: Additional arguments to pass to py_binary

    Example:
        flyte_run(
            name = "run_main_task",
            task_file = "main.py",
            task_function = "main",
            mode = "remote",
            config_file = "flyte_config.yaml",
            log_level = 10,
            params = ["x='hello'", "count=5"],
            deps = ["//package:hello"],
        )
    """
    task_file_name = task_file.split(":")[-1] if ":" in task_file else task_file
    module_name = task_file_name.replace(".py", "")
    package_path = native.package_name()
    package_depth = len(package_path.split("/"))

    args = [
        "--action", "run",
        "--module", module_name,
        "--function", task_function,
        "--mode", mode,
        "--package-path", package_path,
        "--package-depth", str(package_depth),
        "--log-level", str(log_level),
    ]
    for p in params:
        args += ["--param", p]

    _make_flyte_target(name, task_file, args, deps, kwargs)

def flyte_deploy(name, env_file, env_name, dryrun = False, config_file = None, log_level = 30, deps = [], **kwargs):
    """
    A macro to create a py_binary target that deploys a Flyte environment using flyte.deploy().

    Args:
        name: Name of the target
        env_file: Python file containing the TaskEnvironment to deploy
        env_name: The name of the environment to deploy
        dryrun: Whether to perform a dry run (default: False)
        config_file: Path to Flyte config file. If None, uses flyte.init_from_config() to auto-discover .flyte/config.yaml
        log_level: Logging level (int), default 30 (WARNING). Set to 10 for DEBUG.
        deps: Dependencies required by the environment
        **kwargs: Additional arguments to pass to py_binary

    Example:
        flyte_deploy(
            name = "deploy_test_env",
            env_file = "main.py",
            env_name = "test",
            config_file = "flyte_config.yaml",
            log_level = 10,
            dryrun = False,
            deps = ["//package:hello"],
        )
    """
    env_file_name = env_file.split(":")[-1] if ":" in env_file else env_file
    module_name = env_file_name.replace(".py", "")
    package_path = native.package_name()
    package_depth = len(package_path.split("/"))

    args = [
        "--action", "deploy",
        "--module", module_name,
        "--env-name", env_name,
        "--package-path", package_path,
        "--package-depth", str(package_depth),
        "--log-level", str(log_level),
    ]
    if dryrun:
        args.append("--dryrun")

    _make_flyte_target(name, env_file, args, deps, kwargs)

def flyte_build(name, env_file, env_name, config_file = None, log_level = 30, deps = [], **kwargs):
    """
    A macro to create a py_binary target that builds images for a Flyte environment using flyte.build_images().

    Args:
        name: Name of the target
        env_file: Python file containing the TaskEnvironment to build
        env_name: The name of the environment to build
        config_file: Path to Flyte config file. If None, uses flyte.init_from_config() to auto-discover .flyte/config.yaml
        log_level: Logging level (int), default 30 (WARNING). Set to 10 for DEBUG.
        deps: Dependencies required by the environment
        **kwargs: Additional arguments to pass to py_binary

    Example:
        flyte_build(
            name = "build_test_env",
            env_file = "main.py",
            env_name = "test",
            config_file = "flyte_config.yaml",
            log_level = 10,
            deps = ["//package:hello"],
        )
    """
    env_file_name = env_file.split(":")[-1] if ":" in env_file else env_file
    module_name = env_file_name.replace(".py", "")
    package_path = native.package_name()
    package_depth = len(package_path.split("/"))

    args = [
        "--action", "build",
        "--module", module_name,
        "--env-name", env_name,
        "--package-path", package_path,
        "--package-depth", str(package_depth),
        "--log-level", str(log_level),
    ]

    _make_flyte_target(name, env_file, args, deps, kwargs)

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
            default = Label("//bazel:_flyte_cli_bin"),
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
