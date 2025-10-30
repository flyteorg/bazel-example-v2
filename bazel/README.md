# Bazel Rules for Flyte

This directory contains custom Bazel rules for working with Flyte workflows, tasks, and deployments.

## Overview

The `bazel/flyte.bzl` file provides four main rules for integrating Flyte into your Bazel build system:

1. **`flyte_cli`** - Run Flyte CLI commands through Bazel
2. **`flyte_run`** - Execute Flyte tasks locally or remotely using `flyte.run()`
3. **`flyte_deploy`** - Deploy Flyte environments using `flyte.deploy()`
4. **`flyte_build`** - Build Docker images for Flyte environments using `flyte.build_images()`

## Table of Contents

- [Setup](#setup)
- [flyte_cli Rule](#flyte_cli-rule)
- [flyte_run Rule](#flyte_run-rule)
- [flyte_deploy Rule](#flyte_deploy-rule)
- [flyte_build Rule](#flyte_build-rule)
- [Configuration](#configuration)

---

## Setup

### Prerequisites

1. Add `flyte` to your `requirements.txt`:
   ```
   flyte>=1.0.0
   ```

2. The `//bazel` package provides a pre-configured `_flyte_cli_bin` target that all rules use internally. This is already set up in `bazel/BUILD.bazel`.

### Loading the Rules

In your `BUILD.bazel` file, load the rules you need:

```starlark
load("//bazel:flyte.bzl", "flyte_cli", "flyte_run", "flyte_deploy", "flyte_build")
```

---

## flyte_cli Rule

The `flyte_cli` rule creates executable Bazel targets that wrap the Flyte CLI, allowing you to run any Flyte command through Bazel.

### Attributes

| Attribute | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `flyte_args` | `list[string]` | No | `[]` | Arguments to pass to the flyte CLI command |

### Usage

#### Basic CLI Wrapper

Create a generic target that accepts any Flyte command:

```starlark
flyte_cli(
    name = "flyte",
)
```

Run with:
```bash
bazel run //app:flyte -- version
bazel run //app:flyte -- --help
bazel run //app:flyte -- whoami
```

#### Predefined Commands

Create targets with specific commands built-in:

```starlark
flyte_cli(
    name = "flyte_version",
    flyte_args = ["version"],
)

flyte_cli(
    name = "flyte_whoami",
    flyte_args = ["whoami"],
)

flyte_cli(
    name = "flyte_config",
    flyte_args = ["config", "list"],
)
```

Run with:
```bash
bazel run //app:flyte_version
bazel run //app:flyte_whoami
```

### Implementation Details

The `flyte_cli` rule:
1. Creates a wrapper shell script that invokes the Flyte CLI binary
2. Sets up runfiles to include the CLI and all Python dependencies
3. Forwards additional command-line arguments to the Flyte CLI
4. Uses the `//bazel:_flyte_cli_bin` target internally

---

## flyte_run Rule

The `flyte_run` macro creates a `py_binary` target that executes Flyte tasks locally or remotely using the `flyte.run()` Python API.

### Attributes

| Attribute | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `name` | `string` | Yes | - | Name of the target |
| `task_file` | `string` | Yes | - | Python file containing the Flyte task |
| `task_function` | `string` | Yes | - | Name of the task function to run |
| `mode` | `string` | No | `"local"` | Execution mode: `"local"` or `"remote"` |
| `params` | `list[string]` | No | `[]` | Parameters to pass to the task (format: `key=value`) |
| `config_file` | `string` | No | `None` | Path to Flyte config file. If `None`, auto-discovers `.flyte/config.yaml` |
| `deps` | `list[label]` | No | `[]` | Dependencies required by the task |

### Usage

#### Local Execution

Run a task locally with default parameters:

```starlark
flyte_run(
    name = "run_main_local",
    task_file = "main.py",
    task_function = "main",
    mode = "local",
    params = ["x='Hello'", "count=5"],
    deps = [
        "//package:hello",
        requirement("flyte"),
    ],
)
```

Run with:
```bash
bazel run //app:run_main_local
```

#### Remote Execution

Run a task on a remote Flyte cluster:

```starlark
flyte_run(
    name = "run_main_remote",
    task_file = "main.py",
    task_function = "main",
    mode = "remote",
    params = ["x='Remote execution'", "count=10"],
    config_file = ".flyte/config.yaml",  # Optional - auto-discovered if not specified
    deps = [
        "//package:hello",
        requirement("flyte"),
    ],
)
```

Run with:
```bash
bazel run //app:run_main_remote
```

### Parameter Format

Parameters are passed as `key=value` strings where the value is Python code:

```starlark
params = [
    "x='hello'",           # String parameter
    "count=5",             # Integer parameter
    "threshold=0.95",      # Float parameter
    "enabled=True",        # Boolean parameter
    "items=[1, 2, 3]",     # List parameter
]
```

### Configuration

- **Local mode**: Calls `flyte.init()` automatically
- **Remote mode**: Calls `flyte.init_from_config()` with the specified config file or auto-discovers `.flyte/config.yaml`

---

## flyte_deploy Rule

The `flyte_deploy` macro creates a `py_binary` target that deploys Flyte `TaskEnvironment` objects using the `flyte.deploy()` Python API.

### Attributes

| Attribute | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `name` | `string` | Yes | - | Name of the target |
| `env_file` | `string` | Yes | - | Python file containing the TaskEnvironment |
| `env_name` | `string` | Yes | - | Name of the environment to deploy |
| `dryrun` | `bool` | No | `False` | Whether to perform a dry run |
| `config_file` | `string` | No | `None` | Path to Flyte config file. If `None`, auto-discovers `.flyte/config.yaml` |
| `deps` | `list[label]` | No | `[]` | Dependencies required by the environment |

### Usage

#### Deploy an Environment

```starlark
flyte_deploy(
    name = "deploy_test_env",
    env_file = "main.py",
    env_name = "test",
    dryrun = False,
    deps = [
        "//package:hello",
        requirement("flyte"),
    ],
)
```

Run with:
```bash
bazel run //app:deploy_test_env
```

#### Dry Run

Perform a dry run to see what would be deployed without actually deploying:

```starlark
flyte_deploy(
    name = "deploy_test_env_dryrun",
    env_file = "main.py",
    env_name = "test",
    dryrun = True,
    deps = [
        "//package:hello",
        requirement("flyte"),
    ],
)
```

Run with:
```bash
bazel run //app:deploy_test_env_dryrun
```

### TaskEnvironment Lookup

The rule looks for the environment in two ways:
1. As a module-level variable with the specified name
2. As a `TaskEnvironment` instance with a matching `name` attribute

---

## flyte_build Rule

The `flyte_build` macro creates a `py_binary` target that builds Docker images for Flyte environments using the `flyte.build_images()` Python API.

### Attributes

| Attribute | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `name` | `string` | Yes | - | Name of the target |
| `env_file` | `string` | Yes | - | Python file containing the TaskEnvironment |
| `env_name` | `string` | Yes | - | Name of the environment to build |
| `config_file` | `string` | No | `None` | Path to Flyte config file. If `None`, auto-discovers `.flyte/config.yaml` |
| `deps` | `list[label]` | No | `[]` | Dependencies required by the environment |

### Usage

#### Build Images

```starlark
flyte_build(
    name = "build_test_env",
    env_file = "main.py",
    env_name = "test",
    deps = [
        "//package:hello",
        requirement("flyte"),
    ],
)
```

Run with:
```bash
bazel run //app:build_test_env
```

---

## Configuration

### Flyte Config File

All rules that interact with remote Flyte clusters support configuration through a config file:

1. **Explicit config**: Pass `config_file = ".flyte/config.yaml"` to the rule
2. **Auto-discovery**: If `config_file` is not specified, the rules automatically look for `.flyte/config.yaml`

Example `.flyte/config.yaml`:

```yaml
endpoint: flyte.example.com
insecure: false
project: myproject
domain: development
```

### Complete BUILD.bazel Example

Here's a complete example showing all rules in use:

```starlark
load("@rules_python//python:defs.bzl", "py_binary")
load("@pip//:requirements.bzl", "requirement")
load("//bazel:flyte.bzl", "flyte_cli", "flyte_run", "flyte_deploy", "flyte_build")

# Generic Flyte CLI
flyte_cli(
    name = "flyte",
)

# Run task locally
flyte_run(
    name = "run_main_local",
    task_file = "main.py",
    task_function = "main",
    mode = "local",
    params = ["x='Local'", "count=3"],
    deps = [
        "//package:hello",
        requirement("flyte"),
    ],
)

# Run task remotely
flyte_run(
    name = "run_main_remote",
    task_file = "main.py",
    task_function = "main",
    mode = "remote",
    params = ["x='Remote'", "count=5"],
    deps = [
        "//package:hello",
        requirement("flyte"),
    ],
)

# Deploy environment
flyte_deploy(
    name = "deploy_test_env",
    env_file = "main.py",
    env_name = "test",
    dryrun = False,
    deps = [
        "//package:hello",
        requirement("flyte"),
    ],
)

# Build images
flyte_build(
    name = "build_test_env",
    env_file = "main.py",
    env_name = "test",
    deps = [
        "//package:hello",
        requirement("flyte"),
    ],
)
```

---

## Internal Implementation

### Provided Binary

The `//bazel:_flyte_cli_bin` target is provided by the `bazel/BUILD.bazel` file and is used internally by all rules. It wraps the Flyte CLI:

```starlark
# bazel/BUILD.bazel
py_binary(
    name = "_flyte_cli_bin",
    srcs = ["flyte_cli.py"],
    deps = [requirement("flyte")],
    main = "flyte_cli.py",
    visibility = ["//visibility:public"],
)
```

The `flyte_cli.py` wrapper:

```python
#!/usr/bin/env python3
"""Wrapper script to invoke the flyte CLI."""
import sys
from flyte.cli import main

if __name__ == "__main__":
    sys.exit(main())
```

### How It Works

1. **flyte_cli**: Creates a shell script that forwards commands to `_flyte_cli_bin`
2. **flyte_run**: Generates a Python script that imports your task and calls `flyte.run()`
3. **flyte_deploy**: Generates a Python script that imports your environment and calls `flyte.deploy()`
4. **flyte_build**: Generates a Python script that imports your environment and calls `flyte.build_images()`

All generated scripts are created using `genrule` and wrapped as `py_binary` targets with proper dependencies.
