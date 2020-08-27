# bazel_python
A simple way to use Python reproducibly within Bazel.

## One-Time Setup
#### Ubuntu
First, install the packages necessary to build Python with commonly-used
modules. On Ubuntu to get `pip`, `zlib`, and `bz2` modules, this looks like:
```bash
sudo apt install build-essential zlib1g-dev libssl-dev libbz2-dev
```

**NOTE:** if you do not have OpenSSL/`libssl-dev` installed, `pip` package
installation will **not** work and you **will** get unexplained errors about
missing Python dependencies.

Use the `setup_python.sh` script to install a global copy of Python. DARG uses
Python 3.7.4, so you can execute:
```bash
./setup_python.sh 3.7.4 $HOME/.bazel_python
```
You may append `--enable-optimizations` to enable Python build-time
optimizations, however be warned that this can add significantly to the install
time. You may run this script multiple times to install different versions of
Python, however you should always use the same install target directory (e.g.,
`$HOME/.bazel_python` above). Each version will be placed in its own
subdirectory of that target.

#### macOS
On macOS, running the above will likely give a warning about missing SSL
modules. To resolve this, assuming you have Homebrew installed, you may need to
run instead:
```bash
brew install openssl
./setup_python.sh 3.7.4 $HOME/.bazel_python --with-openssl=$(brew --prefix openssl)
```

## Per-Project Usage
1. Add a `requirements.txt` with the pip requirements you need.
2. In your `WORKSPACE` add:
```python
load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")

git_repository(
    name = "bazel_python",
    commit = "{COMMIT_GOES_HERE}",
    remote = "https://github.com/95616ARG/bazel_python.git",
)

load("@bazel_python//:bazel_python.bzl", "bazel_python")

bazel_python()
```
3. In your root `BUILD` file add:
```python
load("@bazel_python//:bazel_python.bzl", "bazel_python_interpreter")

bazel_python_interpreter(
    python_version = "3.7.4",
    requirements_file = "requirements.txt",
)
```

#### Pytest and Coverage
We have support for running Pytest tests with `bazel test //...` as well as
preliminary support for extracting coverage reports.

For Pytest support, first add `pytest` to your `requirements.txt` file and
declare your test files with `py_test` rules depending on `pytest_helper`:
```python
py_test(
    name = "test_name",
    size = "small",
    srcs = ["test_name.py"],
    deps = [
        ...
        "@bazel_python//:pytest_helper",
    ],
)
```
and then structure your test file as follows:
```python
"""Test cases for the abstraction."""
# ... first import system, third-party libraries here ...
try:
    from external.bazel_python.pytest_helper import main
    IN_BAZEL = True
except ImportError:
    IN_BAZEL = False
# ... then import your project libraries here ...

# ... your tests go here ...

if IN_BAZEL:
    main(__name__, __file__)
```

If you will only be running under Bazel (i.e., do not need to support 'raw'
`python3 -m pytest` calls), you can leave out the `try`/`except` and `IN_BAZEL`
checks.

To get coverage support, you can add `coverage` to your `requirements.txt` file
then use the `bazel_python_coverage_report` macro:
```python
bazel_python_coverage_report(
    name = "coverage_report",
    test_paths = ["*"],
    code_paths = ["*.py"],
)
```
Here `test_paths` should be essentially a list of `py_test` targets which can
produce `coverage` outputs. `code_paths` should be a list of Python files in
the repository for which you want to compute coverage. Running
`bazel run coverage_report` should produce an `htmlcov` directory with the
coverage report.

## Known Issues
#### Missing Modules
If you get errors about missing modules (e.g., `pytest not found`), please
triple-check that you have installed OpenSSL libraries. On Ubuntu this looks
like `apt install libssl-dev`.

#### Breaking The Sandbox
Even if you don't use these `bazel_python` rules, you may notice that
`py_binary` rules can include Python libraries that are not explicitly depended
on. This is due to the fact that Bazel creates its sandbox using symbolic
links, and Python will _follow symlinks_ when looking for a package.

#### Bazel-Provided Python Packages
Many Bazel packages come "helpfully" pre-packaged with relevant Python code,
which Bazel will then add to the `PYTHONPATH`. For example, when you depend on
a Python GRPC-Protobuf rule, it will automatically add a copy of the GRPC
Python library to your `PYTHONPATH`. This is normally fine, except that GRPC
Python library is likely outdated and for the wrong Python version. The way to
fix this is to depend on `grpc` in your `requirements.txt`, then remove the
offending parts of `sys.path` before importing `grpc` like so:
```python
import sys
sys.path = [path for path in sys.path if "/com_github_grpc_grpc/" not in path]
import grpc
```
Note this might cause problems if the path to the current repository contains
`/com_github_grpc_grpc/`. We are on the lookout for a better solution
long-term.

#### Non-Hermetic Builds
Although this process ensures everyone is using the same _version_ of Python,
it does not make assurances about the _configuration_ of each of those Python
instances. For example, someone who ran the `setup_python.sh` script with
`--enable-optimizations` might see different performance numbers.  You can
check the output of `setup_python.sh` to see which optional modules were not
installed.

#### Duplicates in `~/.bazelrc`
After building Python, `setup_python.sh` will append to your `~/.bazelrc` file
a pointer to the path to the python parent directory provided. If you
call `setup_python.sh` multiple times (e.g. to install multiple versions or
re-install a single version), then multiple copies of that will be added to
`~/.bazelrc`. These duplicates can be removed safely.

#### `:` Characters in Path
Python's venv hard-codes a number of paths in a way that Bazel violates by
moving everything around all the time. We resolve this by replacing those
hard-coded paths with a relative one that should work at run time in the Bazel
sandbox. However, this find-and-replace is currently done with `sed` using a
`:` character as the delimiter. This means that *If the path to Bazel's
internal sandbox directory has a `:` character, our find and replace will
fail.* If you notice errors that are otherwise unexplained, it may be worth
double-checking that you don't have paths with question marks in them.

#### Installs Twice
For some reason, Bazel seems to enjoy running the pip-installation script
twice, an extra time with the note "for host." I'm not entirely sure why this
is, but it doesn't seem to cause any problems other than slowing down the first
build.

#### Custom Name
Need to support custom directory naming in pywrapper.

## Tips
#### Using Python in a Genrule
To use the interpreter in a genrule, depend on it in the tools and make sure to
source the venv before calling `python3`:
```python
genrule(
    cmd = """
    PYTHON_VENV=$(location //:bazel_python_venv)
    pushd $$PYTHON_VENV/..
    source bazel_python_venv_installed/bin/activate
    popd

    python3 ...
    """,
    tools = ["//:bazel_python_venv"],
)
```

Note that the `activate` script currently assumes you are calling it from right
above `bazel_python_venv_installed`, hence you must change to that directory
first.

## Tested Operating Systems
We have tested these rules on the following operating systems:
* Ubuntu 20.04
* Ubuntu 18.04
* Ubuntu 16.04
* macOS Catalina
