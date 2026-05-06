#!/usr/bin/env bash
# build_zip.sh — Build a Lambda deployment zip for Linux (Amazon Linux 2023).
#
# Usage:
#   ./build_zip.sh                          # default: x86_64, python 3.12, src/, requirements.txt
#   ARCH=arm64 ./build_zip.sh               # build for Graviton
#   PYTHON_VERSION=3.13 ./build_zip.sh      # target a different runtime
#   SRC_DIR=app REQS=requirements/prod.txt ./build_zip.sh
#
# Environment variables (with defaults):
#   ARCH             arm64 | x86_64    (default: x86_64)
#   PYTHON_VERSION   3.12              (matches the Lambda runtime)
#   SRC_DIR          src               (directory containing handler module)
#   REQS             requirements.txt  (pip requirements file)
#   BUILD_DIR        build             (intermediate working directory)
#   OUT              function.zip      (final artifact path)
#
# Output:
#   <OUT>            deployment-ready zip
#   <OUT>.size       human-readable size
#
# Notes:
#   - Uses --platform manylinux2014_<arch> + --only-binary=:all: so wheels are
#     downloaded for Linux even when building from macOS or Windows. Pure-Python
#     wheels are also pulled (manylinux2014 is the lowest-common-denominator tag).
#   - For dependencies that DO NOT publish a manylinux wheel, build inside the
#     official Lambda build image instead (e.g. `sam build --use-container`).
#   - The script is intentionally idempotent: it wipes BUILD_DIR each run.

set -euo pipefail

ARCH="${ARCH:-x86_64}"
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
SRC_DIR="${SRC_DIR:-src}"
REQS="${REQS:-requirements.txt}"
BUILD_DIR="${BUILD_DIR:-build}"
OUT="${OUT:-function.zip}"

case "${ARCH}" in
    x86_64)  PIP_PLATFORM="manylinux2014_x86_64" ;;
    arm64)   PIP_PLATFORM="manylinux2014_aarch64" ;;
    *)
        echo "ARCH must be x86_64 or arm64 (got: ${ARCH})" >&2
        exit 1
        ;;
esac

if [[ ! -d "${SRC_DIR}" ]]; then
    echo "Source directory not found: ${SRC_DIR}" >&2
    exit 1
fi

if [[ ! -f "${REQS}" ]]; then
    echo "Requirements file not found: ${REQS}" >&2
    exit 1
fi

echo "==> Cleaning build directory: ${BUILD_DIR}"
rm -rf "${BUILD_DIR}" "${OUT}"
mkdir -p "${BUILD_DIR}"

echo "==> Installing dependencies for ${ARCH} / python${PYTHON_VERSION}"
pip install \
    --target "${BUILD_DIR}" \
    --platform "${PIP_PLATFORM}" \
    --python-version "${PYTHON_VERSION}" \
    --only-binary=:all: \
    --upgrade \
    -r "${REQS}"

echo "==> Copying source from ${SRC_DIR}/"
# Use rsync to preserve structure but exclude __pycache__ and .pyc files.
if command -v rsync >/dev/null 2>&1; then
    rsync -a \
        --exclude '__pycache__' \
        --exclude '*.pyc' \
        --exclude '*.pyo' \
        --exclude 'tests' \
        "${SRC_DIR}/" "${BUILD_DIR}/"
else
    cp -R "${SRC_DIR}/." "${BUILD_DIR}/"
    find "${BUILD_DIR}" -type d -name '__pycache__' -exec rm -rf {} +
    find "${BUILD_DIR}" -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete
fi

echo "==> Stripping bytecode and dist-info noise"
find "${BUILD_DIR}" -type d -name '__pycache__' -exec rm -rf {} +
find "${BUILD_DIR}" -type f -name '*.pyc' -delete

echo "==> Zipping -> ${OUT}"
( cd "${BUILD_DIR}" && zip -qr "../${OUT}" . )

SIZE_BYTES=$(wc -c < "${OUT}" | tr -d ' ')
SIZE_HUMAN=$(du -h "${OUT}" | awk '{print $1}')
echo "${SIZE_HUMAN}" > "${OUT}.size"

echo
echo "Built: ${OUT}"
echo "Size:  ${SIZE_HUMAN} (${SIZE_BYTES} bytes)"
echo "Arch:  ${ARCH}"
echo "Py:    ${PYTHON_VERSION}"

LIMIT_ZIPPED=$((50 * 1024 * 1024))
if (( SIZE_BYTES > LIMIT_ZIPPED )); then
    echo
    echo "WARNING: zip exceeds the 50 MB direct-upload limit." >&2
    echo "Either upload via S3 (CreateFunction --code S3Bucket/S3Key)," >&2
    echo "split heavy deps into a layer, or switch to a container image." >&2
fi
