# ruff: noqa: T201

"""Shared entry point for flyte_run / flyte_deploy / flyte_build targets.

Replaces per-target Python code generation in flyte.bzl with a single static
file that accepts CLI args.  Each Bazel macro now generates a one-line wrapper
that calls main() here; all real logic lives in lintable, testable Python.
"""

from __future__ import annotations

import argparse
import ast
import atexit
import glob
import importlib
import os
import shutil
import sys
import tempfile

# ---------------------------------------------------------------------------
# Helpers — ported verbatim from the _generate_* functions in flyte.bzl
# ---------------------------------------------------------------------------


def _stage_runfiles(package_depth: int, package_path: str) -> None:
    """Stage Bazel runfiles into a temp directory with dereferenced symlinks.

    Bazel runfiles on macOS and Linux are symlink trees; Flyte's code bundler
    needs real files.  This function:
      1. Copies runfiles into a temp dir with dereferenced symlinks
      2. Skips _solib_* native library directories
      3. Flattens .venv.pth proto-generated code into the staging root
      4. Removes original proto output directories after flattening
    """
    script_dir = os.path.dirname(os.path.abspath(sys.argv[0]))
    runfiles_main = script_dir
    for _ in range(package_depth):
        runfiles_main = os.path.dirname(runfiles_main)

    staging_dir = os.path.realpath(tempfile.mkdtemp(prefix="flyte_bundle_"))
    atexit.register(shutil.rmtree, staging_dir, True)

    for entry in os.listdir(runfiles_main):
        if entry.startswith("_solib_"):
            continue
        src = os.path.join(runfiles_main, entry)
        dst = os.path.join(staging_dir, entry)
        if os.path.isdir(src):
            shutil.copytree(src, dst, symlinks=False)
        else:
            shutil.copy2(src, dst)

    # Flatten .venv.pth entries (proto-generated code) into the staging root.
    runfiles_root = os.path.dirname(runfiles_main)
    site_pkg_dirs = glob.glob(
        os.path.join(runfiles_root, ".*.venv", "lib", "python*", "site-packages")
    )
    for sp_dir in site_pkg_dirs:
        for pth_file in glob.glob(os.path.join(sp_dir, "*.venv.pth")):
            with open(pth_file) as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    resolved = os.path.normpath(os.path.join(sp_dir, line))
                    if resolved.startswith(runfiles_main + os.sep) and os.path.isdir(
                        resolved
                    ):
                        rel_path = os.path.relpath(resolved, runfiles_main)
                        for item in os.listdir(resolved):
                            src_path = os.path.join(resolved, item)
                            dst_path = os.path.join(staging_dir, item)
                            if os.path.isdir(src_path):
                                shutil.copytree(
                                    src_path,
                                    dst_path,
                                    symlinks=False,
                                    dirs_exist_ok=True,
                                )
                            elif not os.path.exists(dst_path):
                                shutil.copy2(src_path, dst_path)
                        staged_orig = os.path.join(staging_dir, rel_path)
                        if os.path.basename(resolved).endswith("_pb") and os.path.isdir(
                            staged_orig
                        ):
                            shutil.rmtree(staged_orig)

    sys.path.insert(0, staging_dir)
    sys.path.insert(0, os.path.join(staging_dir, package_path))
    os.chdir(staging_dir)


def _resolve_extra_pip_packages() -> list[str]:
    """Auto-detect extra pip packages from the Bazel environment.

    The base Flyte image includes flyte and its transitive deps.  Any
    additional pip packages in the Bazel venv are added to the image so that
    task code can import them at runtime.
    """
    import importlib.metadata as im

    base: set[str] = set()
    queue = ["flyte"]
    while queue:
        name = queue.pop()
        key = name.lower().replace("-", "_").replace(".", "_")
        if key in base:
            continue
        base.add(key)
        try:
            reqs = im.requires(name) or []
        except im.PackageNotFoundError:
            continue
        for r in reqs:
            if "; extra" in r:
                continue
            pkg = r.split(";")[0].strip()
            for c in "><=!~[ ":
                pkg = pkg.split(c)[0]
            if pkg:
                queue.append(pkg)

    extras: list[str] = []
    seen: set[str] = set()
    for dist in im.distributions():
        dist_name = dist.metadata["Name"]
        key = dist_name.lower().replace("-", "_").replace(".", "_")
        if key not in base and key not in seen:
            seen.add(key)
            extras.append(dist_name + "==" + dist.version)
    return extras


def _apply_extra_pip_packages(env: object) -> None:
    """Apply auto-detected extra pip packages to a Flyte environment."""
    import flyte

    extra_pkgs = _resolve_extra_pip_packages()
    if extra_pkgs:
        print("Extra pip packages detected from Bazel deps: " + ", ".join(extra_pkgs))
        if isinstance(env.image, str) or env.image is None:
            env.image = flyte.Image.from_debian_base().with_pip_packages(*extra_pkgs)
        else:
            env.image = env.image.with_pip_packages(*extra_pkgs)


def _init_flyte_config(log_level: int) -> None:
    """Initialize Flyte from config.

    Reads .flyte/config.yaml from the workspace root (via
    BUILD_WORKSPACE_DIRECTORY) if it exists, otherwise falls back to
    auto-discovery.
    """
    import flyte

    workspace_dir = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    config_path = (
        os.path.join(workspace_dir, ".flyte", "config.yaml") if workspace_dir else None
    )
    if config_path and os.path.exists(config_path):
        flyte.init_from_config(config_path, log_level=log_level)
    else:
        flyte.init_from_config(log_level=log_level)


def _lookup_env(module: object, env_name: str) -> object:
    """Look up a TaskEnvironment by name from a module.

    First tries getattr for a direct attribute match, then falls back to
    scanning all module attributes for a TaskEnvironment with a matching
    .name property.
    """
    import flyte

    env = getattr(module, env_name, None)
    if env is None:
        for attr_name in dir(module):
            attr = getattr(module, attr_name)
            if isinstance(attr, flyte.TaskEnvironment) and attr.name == env_name:
                env = attr
                break

    if env is None:
        print(f"Error: Could not find environment '{env_name}' in module")
        sys.exit(1)
    return env


def _parse_params(param_list: list[str]) -> dict:
    """Parse key=value parameter strings into a dict.

    Values are interpreted via ast.literal_eval (safe — only parses Python
    literals like ints, strings, lists) so that e.g. "limit=500" becomes
    {"limit": 500}.
    """
    params: dict = {}
    for p in param_list:
        key, value = p.split("=", 1)
        params[key] = ast.literal_eval(value)
    return params


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------


def _action_run(args: argparse.Namespace) -> None:
    """Execute a Flyte task locally or remotely."""
    import flyte

    module = importlib.import_module(args.module)
    task_fn = getattr(module, args.function)

    if args.mode == "remote":
        # Find the first TaskEnvironment in the module for pip auto-detection.
        run_env = None
        for attr_name in dir(module):
            attr = getattr(module, attr_name)
            if isinstance(attr, flyte.TaskEnvironment):
                run_env = attr
                break

        if run_env is not None:
            _apply_extra_pip_packages(run_env)

        _init_flyte_config(args.log_level)
    else:
        workspace_dir = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
        if workspace_dir:
            os.chdir(workspace_dir)
        flyte.init(log_level=args.log_level)

    params = _parse_params(args.param)
    result = flyte.run(task_fn, **params)

    print(f"Task completed. Result: {result}")
    if hasattr(result, "url"):
        print(f"URL: {result.url}")
    if hasattr(result, "outputs"):
        print(f"Outputs: {result.outputs()}")


def _action_deploy(args: argparse.Namespace) -> None:
    """Deploy a Flyte environment."""
    import flyte

    module = importlib.import_module(args.module)
    env = _lookup_env(module, args.env_name)
    _apply_extra_pip_packages(env)
    _init_flyte_config(args.log_level)

    deployments = flyte.deploy(env, dryrun=args.dryrun, copy_style="all")
    print(f"Deployment completed: {deployments}")


def _action_build(args: argparse.Namespace) -> None:
    """Build images for a Flyte environment."""
    import flyte

    module = importlib.import_module(args.module)
    env = _lookup_env(module, args.env_name)
    _apply_extra_pip_packages(env)
    _init_flyte_config(args.log_level)

    image_cache = flyte.build_images(env)
    print(f"Build completed: {image_cache}")


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

_ACTIONS = {
    "run": _action_run,
    "deploy": _action_deploy,
    "build": _action_build,
}


def main() -> None:
    parser = argparse.ArgumentParser(description="Flyte task runner")
    parser.add_argument(
        "--action",
        choices=_ACTIONS,
        required=True,
    )
    parser.add_argument("--module", required=True)
    parser.add_argument("--function")
    parser.add_argument("--env-name")
    parser.add_argument("--mode", default="local")
    parser.add_argument("--package-path", default="")
    parser.add_argument("--package-depth", type=int, default=0)
    parser.add_argument("--log-level", type=int, default=30)
    parser.add_argument("--param", action="append", default=[])
    parser.add_argument("--dryrun", action="store_true")
    args = parser.parse_args()

    if args.mode == "remote" or args.action in ("deploy", "build"):
        _stage_runfiles(args.package_depth, args.package_path)

    _ACTIONS[args.action](args)


if __name__ == "__main__":
    main()
