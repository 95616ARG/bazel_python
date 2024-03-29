#!/bin/bash

# If python is run from the 'main' workspace, then we will have
# bazel_python_venv_installed available right in the current directory. But if
# it's run from a dependency (e.g., GRPC) then it will be under
# bazel_out/.../[mainworkspace]. This searches for the first matching path then
# exits, so it should be reasonably fast in most cases.
# https://unix.stackexchange.com/questions/68414/only-find-first-few-matched-files-using-find
venv_path=$((find -L . -path "*/bazel_python_venv_installed/bin/activate" & ) | head -n 1)
# If venv_path was not found it will be empty and the below will throw an
# error, alerting Bazel something went wrong.
source $venv_path || exit 1
python $@
