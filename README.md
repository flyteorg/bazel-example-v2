# Bazel + Flyte Example

This repository demonstrates how to build and test Python packages with Bazel, and provides custom Bazel rules for working with [Flyte](https://flyte.org/) workflows and tasks.

<!-- docs:start -->
## Quick Start

### Build Everything

```bash
$ bazel build //...
```

### Run Tests

```bash
$ bazel test //...
```

### Run the Main Application

```bash
$ bazel run //app:main
```

---

## Bazel Basics

### Building Packages

This example uses Bazel to build and test a Python package and then use that package in another Python program configured with third-party dependencies.

```bash
$ bazel build //...

INFO: Analyzed 6 targets (1 packages loaded, 2174 targets configured).
INFO: Found 6 targets...
INFO: Elapsed time: 0.301s, Critical Path: 0.01s
INFO: 1 process: 1 internal.
INFO: Build completed successfully, 1 total action
```

### Testing

```bash
$ bazel test //...

INFO: Analyzed 6 targets (0 packages loaded, 0 targets configured).
INFO: Found 4 targets and 2 test targets...
INFO: Elapsed time: 0.130s, Critical Path: 0.00s
INFO: 1 process: 1 internal.
INFO: Build completed successfully, 1 total action
PASSED: //app:main_test
PASSED: //package:test_hello

Executed 0 out of 2 tests: 2 tests pass.
```

### Managing Python Dependencies

Update your `requirements_lock.txt` from `requirements.txt`:

```bash
$ bazel run //app:requirements.update
```

This uses `rules_python` to compile and lock your Python dependencies with hashes for reproducible builds.

---

## Flyte Bazel Rules

This project includes custom Bazel rules for working with Flyte. These rules are located in `bazel/flyte.bzl` and provide four main capabilities:

1. **`flyte_cli`** - Run Flyte CLI commands through Bazel
2. **`flyte_run`** - Execute Flyte tasks locally or remotely
3. **`flyte_deploy`** - Deploy Flyte environments
4. **`flyte_build`** - Build Docker images for Flyte environments

### flyte_cli - Running Flyte CLI Commands

The `flyte_cli` rule allows you to run any Flyte CLI command through Bazel:

```bash
# Run any flyte command
$ bazel run //app:flyte -- version
$ bazel run //app:flyte -- --help
$ bazel run //app:flyte -- whoami
```

### flyte_run - Execute Flyte Tasks

Run Flyte tasks locally or remotely using the `flyte.run()` API:

```bash
# Run a task locally
$ bazel run //app:run_main_local

# Run a task on a remote Flyte cluster
$ bazel run //app:run_main_remote
```

These targets are defined in your `BUILD.bazel` file:

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

### flyte_deploy - Deploy Flyte Environments

Deploy Flyte `TaskEnvironment` objects to a remote cluster:

```bash
# Deploy an environment
$ bazel run //app:deploy_test_env

# Dry run to see what would be deployed
$ bazel run //app:deploy_test_env_dryrun
```

### flyte_build - Build Docker Images

Build Docker images for Flyte environments:

```bash
$ bazel run //app:build_test_env
```

### Custom Entrypoint

The `entrypoint` target provides a flexible way to run Python scripts with all dependencies:

```bash
# Run a specific workflow
$ bazel run //app:entrypoint -- main.py my_wf

# Pass custom parameters
$ bazel run //app:entrypoint -- main.py my_task --param value
```

---

## Documentation

### Complete Flyte Bazel Rules Documentation

For complete documentation on all Flyte Bazel rules, including:
- Detailed attribute descriptions
- Configuration options
- Advanced usage examples
- Implementation details

See **[bazel/README.md](bazel/README.md)**

### BUILD.bazel Examples

The `app/BUILD.bazel` file contains working examples of all the Flyte rules:

```starlark
load("//bazel:flyte.bzl", "flyte_cli", "flyte_run", "flyte_deploy", "flyte_build")

# CLI wrapper
flyte_cli(name = "flyte")

# Local task execution
flyte_run(
    name = "run_main_local",
    task_file = "main.py",
    task_function = "main",
    mode = "local",
    params = ["x='Bazel'", "count=3"],
    deps = ["//package:hello", requirement("flyte")],
)

# Remote task execution
flyte_run(
    name = "run_main_remote",
    task_file = "main.py",
    task_function = "main",
    mode = "remote",
    params = ["x='Remote'", "count=2"],
    deps = ["//package:hello", requirement("flyte")],
)

# Environment deployment
flyte_deploy(
    name = "deploy_test_env",
    env_file = "main.py",
    env_name = "test",
    deps = ["//package:hello", requirement("flyte")],
)

# Image building
flyte_build(
    name = "build_test_env",
    env_file = "main.py",
    env_name = "test",
    deps = ["//package:hello", requirement("flyte")],
)
```

---

## Project Structure

```
.
├── README.md                 # This file
├── MODULE.bazel             # Bazel module configuration
├── bazel/                   # Custom Bazel rules
│   ├── README.md           # Complete documentation for Flyte rules
│   ├── BUILD.bazel         # Internal Flyte CLI binary target
│   ├── flyte.bzl           # Flyte Bazel rules
│   └── flyte_cli.py        # Flyte CLI wrapper
├── app/                     # Main application
│   ├── BUILD.bazel         # Build targets with Flyte rule examples
│   ├── main.py             # Main application and Flyte tasks
│   ├── main_test.py        # Tests
│   ├── requirements.txt    # Python dependencies
│   └── requirements_lock.txt # Locked dependencies
└── package/                 # Example Python package
    ├── BUILD.bazel
    └── hello.py
```

---

## Configuration

### Flyte Configuration

For remote execution (using `flyte_run`, `flyte_deploy`, or `flyte_build` with remote mode), you can configure Flyte in two ways:

1. **Auto-discovery**: Place a config file at `.flyte/config.yaml` (automatically discovered)
2. **Explicit config**: Pass `config_file = "path/to/config.yaml"` to the rule

Example `.flyte/config.yaml`:

```yaml
endpoint: flyte.example.com
insecure: false
project: myproject
domain: development
```

### Python Configuration

Python version and dependencies are configured in `MODULE.bazel`:

```starlark
python.toolchain(
    python_version = "3.11",
    is_default = True,
)

pip.parse(
    hub_name = "pip",
    python_version = "3.11",
    requirements_lock = "//app:requirements_lock.txt",
)
```

---

## Features

- **Reproducible builds** with Bazel
- **Locked Python dependencies** using `rules_python`
- **Integrated Flyte CLI** through Bazel targets
- **Local and remote Flyte execution** with the same codebase
- **Type-safe Flyte deployments** using Python API
- **Docker image building** for Flyte environments
- **Comprehensive testing** with `py_test`

<!-- docs:end -->
