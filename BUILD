exports_files([
    "._dummy_.py",
    "pywrapper.sh",
    "coverage_report.sh",
] + glob(["external/*.BUILD"]))

sh_library(
    name = "pywrapper",
    srcs = ["pywrapper.sh"],
    visibility = ["//:__subpackages__"],
)

py_library(
    name = "pytest_helper",
    srcs = ["pytest_helper.py"],
    visibility = ["//visibility:public"],
)
