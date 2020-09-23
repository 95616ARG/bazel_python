#!/bin/bash

source bazel_python_venv_installed/bin/activate || exit 1
python $@
