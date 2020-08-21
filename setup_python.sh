#!/bin/bash

if [ $# -le 1 ]; then
    echo "This is $(basename $0). Usage:"
    echo "$(basename $0) [version] [/path/to/install/parent/directory] [python configure flags]"
    echo "Example:"
    echo "$(basename $0) 3.7.4 $HOME/.bazel_python --enable-optimizations"
    exit 1
fi

version=$1
shift
install_parent_dir=$1
shift
install_dir=$install_parent_dir/$version

read -p "Installing Python $1. This will *OVERWRITE* $install_dir. Continue? [y/N] " -r
if [[ $REPLY =~ ^[Yy]$ ]]
then
    rm -rf $install_dir
    mkdir -p $install_dir
    cd $install_dir

    curl -OL https://www.python.org/ftp/python/$version/Python-$version.tgz
    tar -xzf Python-$version.tgz
    cd Python-$version

    ./configure --prefix=$install_dir $@

    make -j
    make install
    cd $install_dir
    rm -rf Python-$version
    rm -rf Python-$version.tgz

    echo "Success!"
    echo "Writing Installation Directory to $HOME/.bazelrc"
    echo "If you have run this script multiple times, you may safely remove duplicate lines from $HOME/.bazelrc"
    echo "build --define BAZEL_PYTHON_DIR=$install_parent_dir" >> $HOME/.bazelrc
    echo "run --define BAZEL_PYTHON_DIR=$install_parent_dir" >> $HOME/.bazelrc
else
    echo "Aborting."
fi
