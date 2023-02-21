
def bazel_pybind11(
    name = "pybind11",
    build_file = "@pybind11_bazel//:pybind11.BUILD",
    sha256 = "c9375b7453bef1ba0106849c83881e6b6882d892c9fae5b2572a2192100ffb8a",
    strip_prefix = "pybind11-a54eab92d265337996b8e4b4149d9176c2d428a6",
    urls = ["https://github.com/pybind/pybind11/archive/a54eab92d265337996b8e4b4149d9176c2d428a6.tar.gz"],
):
    native.http_archive(
        name = name,
        build_file = build_file,
        sha256 = sha256,
        strip_prefix = strip_prefix,
        urls = urls,
    )

# https://github.com/pybind/pybind11_bazel/blob/master/build_defs.bzl
# Copyright (c) 2019 The Pybind Development Team. All rights reserved.
#
# All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

"""Build rules for pybind11."""

def register_extension_info(**kwargs):
    pass

PYBIND_COPTS = select({
    "@pybind11//:msvc_compiler": [],
    "//conditions:default": [
        "-fexceptions",
    ],
})

PYBIND_FEATURES = [
    "-use_header_modules",  # Required for pybind11.
    "-parse_headers",
]

PYBIND_DEPS = [
    "@pybind11",
    # "@local_config_python//:python_headers",
    # "@python//:python",
    "@python",
]

# Builds a Python extension module using pybind11.
# This can be directly used in python with the import statement.
# This adds rules for a .so binary file.
def pybind_extension(
        name,
        copts = [],
        features = [],
        linkopts = [],
        tags = [],
        deps = [],
        **kwargs):
    # Mark common dependencies as required for build_cleaner.
    tags = tags + ["req_dep=%s" % dep for dep in PYBIND_DEPS]

    native.cc_binary(
        name = name + ".so",
        copts = copts + PYBIND_COPTS + select({
            "@pybind11//:msvc_compiler": [],
            "//conditions:default": [
                "-fvisibility=hidden",
            ],
        }),
        features = features + PYBIND_FEATURES,
        linkopts = linkopts + select({
            "@pybind11//:msvc_compiler": [],
            "@pybind11//:osx": [],
            "//conditions:default": ["-Wl,-Bsymbolic"],
        }),
        linkshared = 1,
        tags = tags,
        deps = deps + PYBIND_DEPS,
        **kwargs
    )

# Builds a pybind11 compatible library. This can be linked to a pybind_extension.
def pybind_library(
        name,
        copts = [],
        features = [],
        tags = [],
        deps = [],
        **kwargs):
    # Mark common dependencies as required for build_cleaner.
    tags = tags + ["req_dep=%s" % dep for dep in PYBIND_DEPS]

    native.cc_library(
        name = name,
        copts = copts + PYBIND_COPTS,
        features = features + PYBIND_FEATURES,
        tags = tags,
        deps = deps + PYBIND_DEPS,
        **kwargs
    )

# # Builds a C++ test for a pybind_library.
# def pybind_library_test(
#         name,
#         copts = [],
#         features = [],
#         tags = [],
#         deps = [],
#         **kwargs):
#     # Mark common dependencies as required for build_cleaner.
#     tags = tags + ["req_dep=%s" % dep for dep in PYBIND_DEPS]

#     native.cc_test(
#         name = name,
#         copts = copts + PYBIND_COPTS,
#         features = features + PYBIND_FEATURES,
#         tags = tags,
#         deps = deps + PYBIND_DEPS + [
#             "//util/python:python_impl",
#             "//util/python:test_main",
#         ],
#         **kwargs
#     )

# Register extension with build_cleaner.
register_extension_info(
    extension = pybind_extension,
    label_regex_for_dep = "{extension_name}",
)

register_extension_info(
    extension = pybind_library,
    label_regex_for_dep = "{extension_name}",
)

# register_extension_info(
#     extension = pybind_library_test,
#     label_regex_for_dep = "{extension_name}",
# )