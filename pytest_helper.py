"""Helper methods for using Pytest within Bazel."""
import sys
import numpy as np
import pytest
try:
    import coverage
    COVERAGE = True
except ImportError:
    COVERAGE = False
import os

if COVERAGE:
    # We need to do this here, otherwise it won't catch method/class declarations.
    # Also, helpers imports should be before all other local imports.
    cov_file = "%s/coverage.cov" % os.environ["TEST_UNDECLARED_OUTPUTS_DIR"]
    cov = coverage.Coverage(data_file=cov_file)
    cov.start()

def main(script_name, file_name):
    """Test runner that supports Bazel test and the coverage_report.sh script.

    Tests should import this module before importing any other local scripts,
    then call main(__name__, __file__) after declaring their tests.
    """
    if script_name != "__main__":
        return
    exit_code = pytest.main([file_name, "-s"])
    if COVERAGE:
        cov.stop()
        cov.save()
    sys.exit(exit_code)
