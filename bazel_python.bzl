load("@bazel_tools//tools/python:toolchain.bzl", "py_runtime_pair")

def bazel_python(venv_name = "bazel_python_venv"):
    """Workspace rule setting up bazel_python for a repository.

    Arguments
    =========
    @venv_name should match the 'name' argument given to the
        bazel_python_interpreter call in the BUILD file.
    """
    native.register_toolchains("//:" + venv_name + "_toolchain")

def bazel_python_interpreter(
        python_version,
        name = "bazel_python_venv",
        requirements_file = None,
        **kwargs):
    """BUILD rule setting up a bazel_python interpreter (venv).

    Arguments
    =========
    @python_version should be the Python version string to use (e.g. 3.7.4 is
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
        python_version = python_version,
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

def _bazel_python_venv_impl(ctx):
    """A Bazel rule to set up a Python virtual environment.

    Also installs requirements specified by @ctx.attr.requirements_file.
    """
    python_version = ctx.attr.python_version
    use_system = False
    only_warn = ctx.var.get("BAZEL_PYTHON_ONLY_WARN", "false").lower() == "true"
    if "BAZEL_PYTHON_DIR" not in ctx.var:
        if only_warn:
            print("Bazel build flag 'BAZEL_PYTHON_DIR' was not defined. Falling back to the system python. For reproducibility, please run setup_python.sh for " + python_version)
            use_system = True
        else:
            fail("Bazel build flag 'BAZEL_PYTHON_DIR' was not defined. You must run setup_python.sh for " + python_version)
    if use_system:
        python_dir = ""
    else:
        python_parent_dir = ctx.var.get("BAZEL_PYTHON_DIR")
        python_dir = ctx.path(python_parent_dir).dirname.get_child(python_version)
        if not python_dir.exists:
            fail("A bazel-python installation for {python_version} was not found in '{python_parent_dir}/{python_version}'. You must run setup_python.sh for {python_version}".format(
                python_parent_dir=python_parent_dir,
                python_version=python_version
            ))

    venv_dir = ctx.actions.declare_directory("bazel_python_venv_installed")
    inputs = []
    if use_system:
        command = ""
    else:
        command = """
            export PATH={py_dir}/bin:$PATH
            export PATH={py_dir}/include:$PATH
            export PATH={py_dir}/lib:$PATH
            export PATH={py_dir}/share:$PATH
            export PYTHON_PATH={py_dir}:{py_dir}/bin:{py_dir}/include:{py_dir}/lib:{py_dir}/share
        """
    command += """
        python3 -m venv {out_dir} || exit 1
        source {out_dir}/bin/activate || exit 1
    """
    if ctx.attr.requirements_file:
        command += "pip3 install -r " + ctx.file.requirements_file.path + " || exit 1"
        inputs.append(ctx.file.requirements_file)
    for src in ctx.attr.run_after_pip_srcs:
        inputs.extend(src.files.to_list())
    command += ctx.attr.run_after_pip
    command += """
        REPLACEME=$PWD/'{out_dir}'
        REPLACEWITH='$PWD/bazel_python_venv_installed'
        # This prevents sed from trying to modify the directory. We may want to
        # do a more targeted sed in the future.
        rm -rf {out_dir}/bin/__pycache__ || exit 1
        sed -i'' -e s:$REPLACEME:$REPLACEWITH:g {out_dir}/bin/* || exit 1
    """
    ctx.actions.run_shell(
        command = command.format(py_dir = python_dir, out_dir = venv_dir.path),
        inputs = inputs,
        outputs = [venv_dir],
    )
    return [DefaultInfo(files = depset([venv_dir]))]

bazel_python_venv = rule(
    implementation = _bazel_python_venv_impl,
    attrs = {
        "python_version": attr.string(),
        "requirements_file": attr.label(allow_single_file = True),
        "run_after_pip": attr.string(),
        "run_after_pip_srcs": attr.label_list(allow_files = True),
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
