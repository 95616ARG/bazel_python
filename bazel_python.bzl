load("@bazel_tools//tools/python:toolchain.bzl", "py_runtime_pair")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive", "http_file")

""" Using a local pre-installed Python. """

_LOCAL_PYTHON_REPO_BUILD="""
cc_library(
    name = "python",
    srcs = glob(["lib/*.a"]),
    hdrs = glob([
        "include/**/*.h",
        "include/**/**/*.h",
    ]),
    includes = ["include/python3.9"],
    visibility = ["//visibility:public"],
)

exports_files(glob(["bin/**"]))
"""

def _setup_local_python_repository_impl(repository_ctx):
    BAZEL_PYTHON_DIR = repository_ctx.attr.dir \
                    or repository_ctx.os.environ.get("BAZEL_PYTHON_DIR", None)
    if BAZEL_PYTHON_DIR == None:
        fail("Environment variable `BAZEL_PYTHON_DIR` is missing.")

    path = "{}/{}".format(BAZEL_PYTHON_DIR, repository_ctx.attr.python_version)
    repository_ctx.symlink(path, "")
    repository_ctx.file("BUILD",
        content = _LOCAL_PYTHON_REPO_BUILD,
        executable = False,
        legacy_utf8 = True
    )
    return BAZEL_PYTHON_DIR

setup_local_python_repository = repository_rule(
    implementation = _setup_local_python_repository_impl,
    attrs = {
        "python_version": attr.string(),
        "dir": attr.string()
    },
    local = True,
)

def bazel_local_python(
    python_version = "3.9.7",
    name = "python",
    venv_name = "bazel_python_venv"
):
    """Workspace rule setting up bazel_python for a repository from a
       local Python installation.

    Arguments
    =========
    @python_version should be a Python version number in `major.minor.patch`.
    @name is the repository name.
    @venv_name should match the 'name' argument given to the
        bazel_python_interpreter call in the BUILD file.
    """
    native.register_toolchains("//:" + venv_name + "_toolchain")
    setup_local_python_repository(
        name=name,
        python_version=python_version
    )


""" Build a hermetic Python. """

_known_python_archives_sha256 = {
    3: {
        9: {
            7: "a838d3f9360d157040142b715db34f0218e535333696a5569dc6f854604eb9d1"
        }
    }
}

def bazel_hermetic_python(
    python_version = "3.9.7",
    name = "python",
    venv_name = "bazel_python_venv"
):
    """Workspace rule setting up bazel_python for a repository.

    Arguments
    =========
    @python_version should be a Python version number in `major.minor.patch`.
    @name is the repository name.
    @venv_name should match the 'name' argument given to the
        bazel_python_interpreter call in the BUILD file.
    """
    native.register_toolchains("//:" + venv_name + "_toolchain")

    print("""
    =========================================================================================
    Warning: build a hermetic Python is experimental.

    Known issues:
    1. "[33/43] test_pprint -- test_pickle failed (6 errors)" during PGO.
    2. (Optional) `libsqlite3-dev` is required for Jupyter Notebook.

    TODOs:
    1. Build with tcmalloc.
    =========================================================================================
    """)
    py_major, py_minor, py_patch = [int(num) for num in python_version.split(".")]
    http_archive(
        name = name,
        build_file = "@bazel_python//:external/python{major}.{minor}.BUILD".format(
            major=py_major, minor=py_minor),
        sha256 = _known_python_archives_sha256[py_major][py_minor][py_patch],
        strip_prefix = "Python-{}".format(python_version),
        urls = ["https://www.python.org/ftp/python/{0}/Python-{0}.tgz".format(
            python_version)],
    )

def bazel_python_interpreter(
        name = "bazel_python_venv",
        requirements_file = None,
        **kwargs):
    """BUILD rule setting up a bazel_python interpreter (venv).

    Arguments
    =========
    @python_version (deprecated) should be the Python version string to use (e.g. 3.7.4 is
        the standard for DARG projects). You must run the setup_python.sh
        script with this version number.
    @name is your preferred Bazel name for referencing this. The default should
        work unless you run into a name conflict.
    @requirements_file should be the name of a file in the repository to use as
        the pip requirements.
    @kwargs are passed to bazel_python_venv.
    """
    bazel_python_venv(
        name = name,
        requirements_file = requirements_file,
        **kwargs
    )

    # https://stackoverflow.com/questions/47036855
    native.py_runtime(
        name = name + "_runtime",
        files = ["//:" + name],
        interpreter = "@bazel_python//:pywrapper.sh",
        python_version = "PY3",
    )

    # https://github.com/bazelbuild/rules_python/blob/master/proposals/2019-02-12-design-for-a-python-toolchain.md
    native.constraint_value(
        name = name + "_constraint",
        constraint_setting = "@bazel_tools//tools/python:py3_interpreter_path",
    )

    native.platform(
        name = name + "_platform",
        constraint_values = [
            ":python3_constraint",
        ],
    )

    py_runtime_pair(
        name = name + "_runtime_pair",
        py3_runtime = name + "_runtime",
    )

    native.toolchain(
        name = name + "_toolchain",
        target_compatible_with = [],
        toolchain = "//:" + name + "_runtime_pair",
        toolchain_type = "@bazel_tools//tools/python:toolchain_type",
    )

# def _bazel_python_install_external(ctx, srcs):
#     outs = []
#     for src in srcs:
#         for file in src.files.to_list():
#             out = ctx.actions.declare_file("{dir}/{name}".format(dir=bazel_python_external_bin, name=file.basename))
#             outs.append(out)
#             print(out.path)
#             ctx.actions.symlink(output=out, target_file=file)

#     return outs

def _resolve_external_index(ctx, index_file_path, srcs):

    files = [f for src in srcs for f in src.files.to_list()]

    index = ctx.actions.declare_file(index_file_path)
    ctx.actions.write(
        output=index,
        content="\n".join([f.path for f in files])
    )

    return index, files

def _bazel_python_venv_impl(ctx):
    """A Bazel rule to set up a Python virtual environment.

    Also installs requirements specified by @ctx.attr.requirements_file.
    """
    tool_inputs, tool_input_mfs = ctx.resolve_tools(tools = [ctx.attr.python])
    venv_dir = ctx.actions.declare_directory("bazel_python_venv_installed")

    inputs = []

    inputs_setup = [ f for s in ctx.attr.setups for f in s.files.to_list() ]
    index_setup = ctx.actions.declare_file("_external_setup_to_install")
    ctx.actions.write(
        output=index_setup,
        content="\n".join([ s.label.workspace_root for s in ctx.attr.setups ])
    )

    inputs.append(index_setup)
    inputs.extend(inputs_setup)

    index_bin, inputs_bin = _resolve_external_index(ctx, "_external_bin_to_install", ctx.attr.bins)

    inputs.append(index_bin)
    inputs.extend(inputs_bin)

    index_lib, inputs_lib = _resolve_external_index(ctx, "_external_lib_to_install", ctx.attr.libs)

    inputs.append(index_lib)
    inputs.extend(inputs_lib)

    """ Setup venv. """
    command = """
        set -e

        $(readlink -f {py_executable}) -m venv {venv_dir} || exit 1
        source {venv_dir}/bin/activate || exit 1
        export venv_path={venv_dir}
        export bazel_bin_path={bazel_bin_dir}
        export PATH=$PWD/{venv_dir}/bin:$PWD/{venv_dir}/include:$PWD/{venv_dir}/lib:$PWD/{venv_dir}/share:$PATH
        export LD_LIBRARY_PATH=$PWD/{venv_dir}/lib:$LD_LIBRARY_PATH
        export PYTHONPATH=$PWD/{venv_dir}:$PWD/{venv_dir}/bin:$PWD/{venv_dir}/include:$PWD/{venv_dir}/lib:$PWD/{venv_dir}/share

        python3 -m pip install --upgrade pip

        for _external_bin_src in $(cat {index_bin})
        do
            echo $_external_bin_src
            ln -sfn $(readlink $_external_bin_src) $PWD/{venv_dir}/bin
        done
        rm {index_bin}

        for _external_lib_src in $(cat {index_lib})
        do
            echo $_external_lib_src
            ln -sfn $(readlink $_external_lib_src) $PWD/{venv_dir}/lib
        done
        rm {index_lib}

        for _external_setup_prefix in $(cat {index_setup})
        do
            _external_setup_file=$(find . -path "*/$_external_setup_prefix/*/setup.py" | head -n 1)
            pushd $(dirname $_external_setup_file)
            python3 ./setup.py install || exit 1
            popd
        done
        rm {index_setup}

    """

    """ Install requirements.txt. """
    if ctx.attr.requirements_file:
        command += "pip3 install -r " + ctx.file.requirements_file.path + " || exit 1"
        inputs.append(ctx.file.requirements_file)

    """ Include resources. """
    for src in ctx.attr.data:
        inputs.extend(src.files.to_list())

    """ Append post-pip scripts. """
    command += ctx.attr.run_after_pip

    command += """
        REPLACEME=$PWD/'{venv_dir}'
        REPLACEWITH='$PWD/bazel_python_venv_installed'
        # This prevents sed from trying to modify the directory. We may want to
        # do a more targeted sed in the future.
        rm -rf {venv_dir}/bin/__pycache__ || exit 1
        sed -i'' -e s:$REPLACEME:$REPLACEWITH:g {venv_dir}/bin/* || exit 1
    """
    command = command.format(
        py_executable = ctx.executable.python.path,
        venv_dir = venv_dir.path,
        bazel_bin_dir = ctx.bin_dir.path,
        index_bin = index_bin.path,
        index_lib = index_lib.path,
        index_setup = index_setup.path,
    )

    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [venv_dir],
        tools = tool_inputs,
        command = command
    )

    return [DefaultInfo(files = depset([venv_dir]))]

bazel_python_venv = rule(
    implementation = _bazel_python_venv_impl,
    attrs = {
        "requirements_file": attr.label(allow_single_file = True),
        "bins": attr.label_list(allow_files = True),
        "libs": attr.label_list(allow_files = True),
        "setups": attr.label_list(allow_files = True),
        "data": attr.label_list(allow_files = True),
        "run_after_pip": attr.string(),
        "python": attr.label(
            executable = True,
            allow_single_file = True,
            cfg = 'exec',
            default = Label("@python//:bin/python3"),
        ),
    },
)

def bazel_python_coverage_report(name, test_paths, code_paths):
    """Adds a rule to build the coverage report.

    @name is the name of the target which, when run, creates the coverage
        report.
    @test_paths should be a list of the py_test targets for which coverage
        has been run. Bash wildcards are supported.
    @code_paths should point to the Python code for which you want to compute
        the coverage.
    """
    test_paths = " ".join([
        "bazel-out/*/testlogs/" + test_path + "/test.outputs/outputs.zip"
        for test_path in test_paths])
    code_paths = " ".join(code_paths)
    if "'" in test_paths or "'" in code_paths:
        fail("Quotation marks in paths names not yet supported.")
    # For generating the coverage report.
    native.sh_binary(
        name = name,
        srcs = ["@bazel_python//:coverage_report.sh"],
        deps = [":_dummy_coverage_report"],
        args = ["'" + test_paths + "'", "'" + code_paths + "'"],
    )

    # This is only to get bazel_python_venv as a data dependency for
    # coverage_report above. For some reason, this doesn't work if we directly put
    # it on the sh_binary. This is a known issue:
    # https://github.com/bazelbuild/bazel/issues/1147#issuecomment-428698802
    native.sh_library(
        name = "_dummy_coverage_report",
        srcs = ["@bazel_python//:coverage_report.sh"],
        data = ["//:bazel_python_venv"],
    )
