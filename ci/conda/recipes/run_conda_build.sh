# SPDX-FileCopyrightText: Copyright (c) 2022-2023, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

NUMARGS=$#
ARGS=$*

function hasArg {
    (( ${NUMARGS} != 0 )) && (echo " ${ARGS} " | grep -q " $1 ")
}

function get_version() {
   echo "$(git describe --tags | grep -o -E '^([^-]*?)')"
}

# Color variables
export b="\033[0;36m"
export g="\033[0;32m"
export r="\033[0;31m"
export e="\033[0;90m"
export y="\033[0;33m"
export x="\033[0m"

# Ensure yes is always selected otherwise it can stop halfway through on a prelink message
export CONDA_ALWAYS_YES=true

# Change this to switch between build/mambabuild/debug
export CONDA_COMMAND=${CONDA_COMMAND:-"mambabuild"}

# Get the path to the morpheus git folder
export MORPHEUS_ROOT=${MORPHEUS_ROOT:-$(git rev-parse --show-toplevel)}

# Export script_env variables that must be set for conda build
export CMAKE_CUDA_ARCHITECTURES=${CMAKE_CUDA_ARCHITECTURES:-"RAPIDS"}
export MORPHEUS_PYTHON_BUILD_STUBS=${MORPHEUS_PYTHON_BUILD_STUBS:-"ON"}
export MORPHEUS_CACHE_DIR=${MORPHEUS_CACHE_DIR:-"${MORPHEUS_ROOT}/.cache"}
export PARALLEL_LEVEL=${PARALLEL_LEVEL:-$(nproc)}

# Set CONDA_CHANNEL_ALIAS to mimic the conda config channel_alias property during the build
CONDA_CHANNEL_ALIAS=${CONDA_CHANNEL_ALIAS:-""}
export USE_SCCACHE=${USE_SCCACHE:-""}

export CMAKE_GENERATOR="Ninja"

# Export variables for the cache
export CCACHE_DIR="${MORPHEUS_CACHE_DIR}/ccache"
export CCACHE_NOHASHDIR=1

# Ensure the necessary folders exist before continuing
mkdir -p ${MORPHEUS_CACHE_DIR}
mkdir -p ${CCACHE_DIR}

# Local builds use ccache
# ci builds will use sccache which is a ccache work-alike but uses an S3 backend
# (https://github.com/mozilla/sccache)
if [[ "${USE_SCCACHE}" == "" ]]; then
   # Export CCACHE variables
   export CMAKE_C_COMPILER_LAUNCHER="ccache"
   export CMAKE_CXX_COMPILER_LAUNCHER="ccache"
   export CMAKE_CUDA_COMPILER_LAUNCHER="ccache"
else
   export CMAKE_C_COMPILER_LAUNCHER="sccache"
   export CMAKE_CXX_COMPILER_LAUNCHER="sccache"
   export CMAKE_CUDA_COMPILER_LAUNCHER="sccache"
fi

# Holds the arguments in an array to allow for complex json objects
CONDA_ARGS_ARRAY=()

# Some default args
CONDA_ARGS_ARRAY+=("--use-local")

if [[ "${CONDA_COMMAND}" == "mambabuild" || "${CONDA_COMMAND}" == "build" ]]; then
   # Remove the timestamp from the work folder to allow caching to work better
   CONDA_ARGS_ARRAY+=("--build-id-pat" "{n}-{v}")
fi

# And default channels (with optional channel alias)
CONDA_ARGS_ARRAY+=("-c" "${CONDA_CHANNEL_ALIAS:+"${CONDA_CHANNEL_ALIAS%/}/"}rapidsai")
CONDA_ARGS_ARRAY+=("-c" "${CONDA_CHANNEL_ALIAS:+"${CONDA_CHANNEL_ALIAS%/}/"}nvidia/label/cuda-11.8.0")
CONDA_ARGS_ARRAY+=("-c" "${CONDA_CHANNEL_ALIAS:+"${CONDA_CHANNEL_ALIAS%/}/"}nvidia")
CONDA_ARGS_ARRAY+=("-c" "${CONDA_CHANNEL_ALIAS:+"${CONDA_CHANNEL_ALIAS%/}/"}nvidia/label/dev")
CONDA_ARGS_ARRAY+=("-c" "${CONDA_CHANNEL_ALIAS:+"${CONDA_CHANNEL_ALIAS%/}/"}pytorch")
CONDA_ARGS_ARRAY+=("-c" "${CONDA_CHANNEL_ALIAS:+"${CONDA_CHANNEL_ALIAS%/}/"}conda-forge")

if hasArg morpheus; then
   # Set GIT_VERSION to set the project version inside of meta.yaml
   export GIT_VERSION="$(get_version)"

   echo "Running conda-build for morpheus v${GIT_VERSION}..."
   set -x
   conda ${CONDA_COMMAND} "${CONDA_ARGS_ARRAY[@]}" ${CONDA_ARGS} ci/conda/recipes/morpheus
   set +x
fi

if hasArg pydebug; then
  export MORPHEUS_PYTHON_VER=$(python --version | cut -d ' ' -f 2)

  echo "Running conda-build for python-dbg..."
  set -x
  conda ${CONDA_COMMAND} "${CONDA_ARGS_ARRAY[@]}" ${CONDA_ARGS} ./ci/conda/recipes/python-dbg
  set +x
fi
