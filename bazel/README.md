# Bazel Rules

This directory contains custom Bazel rules used across the project.

## Flyte CLI Rule

The `flyte_cli` rule provides a convenient way to run Flyte CLI commands through Bazel targets.

### Overview

The `flyte_cli` rule creates executable Bazel targets that wrap the Flyte CLI, allowing you to run Flyte commands as part of your Bazel workflow. This ensures consistent execution environments and proper dependency management.

### Setup

To use the `flyte_cli` rule in your BUILD.bazel file:

1. Load the rule:
   ```starlark
   load("//bazel:flyte.bzl", "flyte_cli")
   ```

2. Create a py_binary target for the Flyte CLI entry point:
   ```starlark
   py_binary(
       name = "_flyte_cli_bin",
       srcs = ["flyte_cli.py"],
       deps = [
           requirement("flyte"),
       ],
       main = "flyte_cli.py",
   )
   ```

3. Define `flyte_cli` targets with the commands you want to run.

### Usage

#### Basic Usage

Create a simple Flyte CLI target that accepts any arguments:

```starlark
flyte_cli(
    name = "flyte",
)
```

Run with:
```bash
bazel run //app:flyte -- <any-flyte-command>
```

#### With Predefined Arguments

Create targets with predefined Flyte commands:

```starlark
flyte_cli(
    name = "flyte_help",
    flyte_args = ["--help"],
)

flyte_cli(
    name = "flyte_whoami",
    flyte_args = ["whoami"],
)

flyte_cli(
    name = "flyte_version",
    flyte_args = ["version"],
)
```

Run with:
```bash
bazel run //app:flyte_help
bazel run //app:flyte_whoami
bazel run //app:flyte_version
```

### Rule Attributes

- `flyte_args` (optional, list of strings): Arguments to pass to the flyte CLI command
  - Default: `[]`
  - Example: `["version"]`, `["--help"]`, `["config", "list"]`

### Implementation Details

The rule works by:
1. Creating a wrapper shell script that invokes the Flyte CLI binary
2. Setting up runfiles to include the Flyte CLI and all its Python dependencies
3. Forwarding any additional command-line arguments to the Flyte CLI

The internal `_flyte_cli` attribute points to the py_binary target that contains the actual Flyte CLI implementation.

### Example BUILD.bazel

Here's a complete example:

```starlark
load("@rules_python//python:defs.bzl", "py_binary")
load("@pip//:requirements.bzl", "requirement")
load("//bazel:flyte.bzl", "flyte_cli")

# Flyte CLI entry point (internal dependency for flyte_cli rule)
py_binary(
    name = "_flyte_cli_bin",
    srcs = ["flyte_cli.py"],
    deps = [
        requirement("flyte"),
    ],
    main = "flyte_cli.py",
)

# Generic flyte CLI target
flyte_cli(
    name = "flyte",
)

# Specific flyte commands
flyte_cli(
    name = "flyte_version",
    flyte_args = ["version"],
)

flyte_cli(
    name = "flyte_config",
    flyte_args = ["config", "list"],
)
```

### Requirements

- The Flyte Python package must be included in your requirements.txt
- A `flyte_cli.py` wrapper script that invokes the Flyte CLI main function
- The `_flyte_cli_bin` py_binary target must be defined in the same package where you use the rule

### Example flyte_cli.py

```python
#!/usr/bin/env python3
"""Wrapper script to invoke the flyte CLI."""
import sys
from flyte.cli import main

if __name__ == "__main__":
    sys.exit(main())
```
