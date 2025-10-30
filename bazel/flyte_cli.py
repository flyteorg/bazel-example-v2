#!/usr/bin/env python3
"""Wrapper script to invoke the flyte CLI."""
import sys
from flyte.cli import main

if __name__ == "__main__":
    sys.exit(main())
