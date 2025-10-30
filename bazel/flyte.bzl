"""Bazel rules for running Flyte CLI commands and Python API functions."""

load("@rules_python//python:defs.bzl", "py_binary")

def flyte_run(name, task_file, task_function, mode = "local", params = [], config_file = None, deps = [], **kwargs):
    """
    A macro to create a py_binary target that runs Flyte tasks locally or remotely using flyte.run().

    Args:
        name: Name of the target
        task_file: The Python file containing the Flyte task
        task_function: The name of the task function to run
        mode: Execution mode: 'local' or 'remote' (default: 'local')
        params: Parameters to pass to the task (format: key=value)
        config_file: Path to Flyte config file (used for remote mode). If None, uses flyte.init_from_config() to auto-discover .flyte/config.yaml
        deps: Dependencies required by the task
        **kwargs: Additional arguments to pass to py_binary

    Example:
        flyte_run(
            name = "run_main_task",
            task_file = "main.py",
            task_function = "main",
            mode = "remote",
            config_file = "flyte_config.yaml",
            params = ["x='hello'", "count=5"],
            deps = ["//package:hello"],
        )
    """

    # Build parameter arguments as Python dictionary
    params_dict = "{"
    for p in params:
        parts = p.split("=", 1)
        key = parts[0]
        value = parts[1]
        params_dict += '"%s": %s, ' % (key, value)
    params_dict += "}"

    # Get the task file name without the label prefix and extension
    task_file_name = task_file.split(":")[-1] if ":" in task_file else task_file
    module_name = task_file_name.replace(".py", "")

    # Create a Python script that uses flyte.run()
    # If config_file is provided, use it explicitly. Otherwise, let flyte.init_from_config()
    # automatically discover the config in .flyte/config.yaml
    if config_file:
        init_code = """  config_path = "{config_path}"
  if os.path.exists(config_path):
    flyte.init_from_config(config_path)
  else:
    print(f"Error: Config file '{{config_path}}' not found")
    sys.exit(1)""".format(config_path = config_file)
    else:
        init_code = """  # Let flyte.init_from_config() automatically find .flyte/config.yaml
  flyte.init_from_config()"""

    script_content = """import sys
import os
import flyte

# Import the task module directly
import {module_name} as task_module

# Get the task function
task_fn = getattr(task_module, "{task_function}")

# Initialize flyte
if "{mode}" == "local":
  flyte.init()
else:
{init_code}

# Parse additional arguments from command line
params = {params_dict}

# Run the task
result = flyte.run(task_fn, **params)

print(f"Task completed. Result: {{result}}")
if hasattr(result, 'url'):
    print(f"URL: {{result.url}}")
if hasattr(result, 'outputs'):
    print(f"Outputs: {{result.outputs()}}")
""".format(
        module_name = module_name,
        task_function = task_function,
        mode = mode,
        init_code = init_code,
        params_dict = params_dict,
    )

    # Write the Python script to a file
    script_name = name + "_runner.py"
    native.genrule(
        name = name + "_gen_runner",
        outs = [script_name],
        cmd = "cat > $@ <<'EOF'\n" + script_content + "\nEOF",
    )

    # Create a py_binary that runs the script
    # We need to add the current package to imports so the task file can be imported
    py_binary(
        name = name,
        srcs = [script_name, task_file],
        main = script_name,
        deps = deps,
        imports = ["."],
        **kwargs
    )


def flyte_deploy(name, env_file, env_name, dryrun = False, config_file = None, deps = [], **kwargs):
    """
    A macro to create a py_binary target that deploys a Flyte environment using flyte.deploy().

    Args:
        name: Name of the target
        env_file: Python file containing the TaskEnvironment to deploy
        env_name: The name of the environment to deploy
        dryrun: Whether to perform a dry run (default: False)
        config_file: Path to Flyte config file. If None, uses flyte.init_from_config() to auto-discover .flyte/config.yaml
        deps: Dependencies required by the environment
        **kwargs: Additional arguments to pass to py_binary

    Example:
        flyte_deploy(
            name = "deploy_test_env",
            env_file = "main.py",
            env_name = "test",
            config_file = "flyte_config.yaml",
            dryrun = False,
            deps = ["//package:hello"],
        )
    """

    # Get the env file name without the label prefix and extension
    env_file_name = env_file.split(":")[-1] if ":" in env_file else env_file
    module_name = env_file_name.replace(".py", "")

    # Create a Python script that uses flyte.deploy()
    # If config_file is provided, use it explicitly. Otherwise, let flyte.init_from_config()
    # automatically discover the config in .flyte/config.yaml
    if config_file:
        init_code = """config_path = "{config_path}"
if os.path.exists(config_path):
    flyte.init_from_config(config_path)
else:
    print(f"Error: Config file '{{config_path}}' not found")
    sys.exit(1)""".format(config_path = config_file)
    else:
        init_code = """# Let flyte.init_from_config() automatically find .flyte/config.yaml
flyte.init_from_config()"""

    script_content = """import sys
import os
import flyte

# Import the environment module directly
import {module_name} as env_module

# Get the environment by name
env_to_deploy = getattr(env_module, "{env_name}", None)
if env_to_deploy is None:
    # Try to find TaskEnvironment instances
    for attr_name in dir(env_module):
        attr = getattr(env_module, attr_name)
        if isinstance(attr, flyte.TaskEnvironment) and attr.name == "{env_name}":
            env_to_deploy = attr
            break

if env_to_deploy is None:
    print(f"Error: Could not find environment '{env_name}' in module")
    sys.exit(1)

# Initialize flyte
{init_code}

# Deploy the environment
deployments = flyte.deploy(
    envs=env_to_deploy,
    dryrun={dryrun},
    version=None,
    interactive_mode=None,
    copy_style=None,
)

print(f"Deployment completed: {{deployments}}")
""".format(
        module_name = module_name,
        env_name = env_name,
        init_code = init_code,
        dryrun = "True" if dryrun else "False",
    )

    # Write the Python script to a file
    script_name = name + "_deployer.py"
    native.genrule(
        name = name + "_gen_deployer",
        outs = [script_name],
        cmd = "cat > $@ <<'EOF'\n" + script_content + "\nEOF",
    )

    # Create a py_binary that runs the script
    # We need to add the current package to imports so the env file can be imported
    py_binary(
        name = name,
        srcs = [script_name, env_file],
        main = script_name,
        deps = deps,
        imports = ["."],
        **kwargs
    )

def flyte_build(name, env_file, env_name, config_file = None, deps = [], **kwargs):
    """
    A macro to create a py_binary target that builds images for a Flyte environment using flyte.build_images().

    Args:
        name: Name of the target
        env_file: Python file containing the TaskEnvironment to build
        env_name: The name of the environment to build
        config_file: Path to Flyte config file. If None, uses flyte.init_from_config() to auto-discover .flyte/config.yaml
        deps: Dependencies required by the environment
        **kwargs: Additional arguments to pass to py_binary

    Example:
        flyte_build(
            name = "build_test_env",
            env_file = "main.py",
            env_name = "test",
            config_file = "flyte_config.yaml",
            deps = ["//package:hello"],
        )
    """

    # Get the env file name without the label prefix and extension
    env_file_name = env_file.split(":")[-1] if ":" in env_file else env_file
    module_name = env_file_name.replace(".py", "")

    # Create a Python script that uses flyte.build_images()
    # If config_file is provided, use it explicitly. Otherwise, let flyte.init_from_config()
    # automatically discover the config in .flyte/config.yaml
    if config_file:
        init_code = """config_path = "{config_path}"
if os.path.exists(config_path):
    flyte.init_from_config(config_path)
else:
    print(f"Error: Config file '{{config_path}}' not found")
    sys.exit(1)""".format(config_path = config_file)
    else:
        init_code = """# Let flyte.init_from_config() automatically find .flyte/config.yaml
flyte.init_from_config()"""

    script_content = """import sys
import os
import flyte

# Import the environment module directly
import {module_name} as env_module

# Get the environment by name
env_to_build = getattr(env_module, "{env_name}", None)
if env_to_build is None:
    # Try to find TaskEnvironment instances
    for attr_name in dir(env_module):
        attr = getattr(env_module, attr_name)
        if isinstance(attr, flyte.TaskEnvironment) and attr.name == "{env_name}":
            env_to_build = attr
            break

if env_to_build is None:
    print(f"Error: Could not find environment '{env_name}' in module")
    sys.exit(1)

# Initialize flyte
{init_code}

# Build the environment images
image_cache = flyte.build_images(envs=env_to_build)

print(f"Build completed: {{image_cache}}")
""".format(
        module_name = module_name,
        env_name = env_name,
        init_code = init_code,
    )

    # Write the Python script to a file
    script_name = name + "_builder.py"
    native.genrule(
        name = name + "_gen_builder",
        outs = [script_name],
        cmd = "cat > $@ <<'EOF'\n" + script_content + "\nEOF",
    )

    # Create a py_binary that runs the script
    # We need to add the current package to imports so the env file can be imported
    py_binary(
        name = name,
        srcs = [script_name, env_file],
        main = script_name,
        deps = deps,
        imports = ["."],
        **kwargs
    )

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
