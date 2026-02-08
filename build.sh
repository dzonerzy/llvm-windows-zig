#!/bin/bash
set -euo pipefail

LLVM_VERSION="${1:-21.1.8}"
JOBS="${2:-$(nproc)}"
SRCDIR="llvm-project-${LLVM_VERSION}.src"
TARBALL="${SRCDIR}.tar.xz"

# All supported targets: zig-triple -> (cmake-system-name, cmake-host-triple)
TARGETS=(
    "x86_64-linux-gnu"
    "aarch64-linux-gnu"
    "x86_64-windows-gnu"
    "aarch64-windows-gnu"
    "aarch64-macos"
)

# Build a specific target or all
BUILD_TARGETS="${3:-all}"

echo "=== LLVM ${LLVM_VERSION} cross-compiler (via zig cc) ==="

# Check for zig
if ! command -v zig &>/dev/null; then
    echo "ERROR: zig not found in PATH"
    exit 1
fi
echo "Using: $(zig version)"

# Download source if needed
if [ ! -d "llvm-project" ]; then
    if [ ! -f "${TARBALL}" ]; then
        echo "Downloading LLVM ${LLVM_VERSION} source..."
        wget -q --show-progress \
            "https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}/${TARBALL}"
    fi
    echo "Extracting..."
    tar xf "${TARBALL}"
    mv "${SRCDIR}" llvm-project
fi

build_target() {
    local ZIG_TARGET="$1"

    # Derive names from zig target
    local ARCH="${ZIG_TARGET%%-*}"
    local REST="${ZIG_TARGET#*-}"
    local OS="${REST%%-*}"

    # Normalize platform name for output
    local PLATFORM_OS
    local CMAKE_SYSTEM_NAME
    local CMAKE_HOST_TRIPLE
    case "${OS}" in
        linux)
            PLATFORM_OS="linux"
            CMAKE_SYSTEM_NAME="Linux"
            CMAKE_HOST_TRIPLE="${ARCH}-unknown-linux-gnu"
            ;;
        windows)
            PLATFORM_OS="windows"
            CMAKE_SYSTEM_NAME="Windows"
            CMAKE_HOST_TRIPLE="${ARCH}-w64-mingw32"
            ;;
        macos)
            PLATFORM_OS="macos"
            CMAKE_SYSTEM_NAME="Darwin"
            CMAKE_HOST_TRIPLE="${ARCH}-apple-darwin"
            ;;
    esac

    local OUTDIR="llvm-${LLVM_VERSION}-${ARCH}-${PLATFORM_OS}"
    local BUILDDIR="build-${ARCH}-${PLATFORM_OS}"

    echo ""
    echo "=== Building for ${ARCH}-${PLATFORM_OS} (zig target: ${ZIG_TARGET}) ==="

    # Create zig cc/c++ wrapper scripts for this target
    local WRAPDIR="wrappers-${ARCH}-${PLATFORM_OS}"
    mkdir -p "${WRAPDIR}"
    cat > "${WRAPDIR}/zig-cc" << WRAPPER
#!/bin/bash
zig cc -target ${ZIG_TARGET} -g0 "\$@"
WRAPPER
    cat > "${WRAPDIR}/zig-c++" << WRAPPER
#!/bin/bash
zig c++ -target ${ZIG_TARGET} -g0 "\$@"
WRAPPER
    chmod +x "${WRAPDIR}/zig-cc" "${WRAPDIR}/zig-c++"
    local WRAPPER_DIR="$(pwd)/${WRAPDIR}"

    # Configure
    echo "  Configuring..."
    cmake -G Ninja -S llvm-project/llvm -B "${BUILDDIR}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SYSTEM_NAME="${CMAKE_SYSTEM_NAME}" \
        -DCMAKE_C_COMPILER="${WRAPPER_DIR}/zig-cc" \
        -DCMAKE_CXX_COMPILER="${WRAPPER_DIR}/zig-c++" \
        -DCMAKE_AR="$(which llvm-ar)" \
        -DCMAKE_RANLIB="$(which llvm-ranlib)" \
        -DLLVM_TARGETS_TO_BUILD="X86" \
        -DLLVM_ENABLE_PROJECTS="" \
        -DLLVM_BUILD_TOOLS=OFF \
        -DLLVM_BUILD_UTILS=OFF \
        -DLLVM_BUILD_RUNTIME=OFF \
        -DLLVM_INCLUDE_TESTS=OFF \
        -DLLVM_INCLUDE_BENCHMARKS=OFF \
        -DLLVM_INCLUDE_EXAMPLES=OFF \
        -DLLVM_INCLUDE_DOCS=OFF \
        -DLLVM_ENABLE_ZLIB=OFF \
        -DLLVM_ENABLE_ZSTD=OFF \
        -DLLVM_ENABLE_TERMINFO=OFF \
        -DLLVM_ENABLE_LIBXML2=OFF \
        -DBUILD_SHARED_LIBS=OFF \
        -DLLVM_HOST_TRIPLE="${CMAKE_HOST_TRIPLE}" \
        > /dev/null 2>&1

    # Build
    echo "  Building with ${JOBS} jobs..."
    ninja -C "${BUILDDIR}" -j"${JOBS}"

    # Package
    echo "  Packaging..."
    rm -rf "${OUTDIR}"
    mkdir -p "${OUTDIR}/lib" "${OUTDIR}/include"

    cp "${BUILDDIR}"/lib/*.a "${OUTDIR}/lib/"
    cp -r llvm-project/llvm/include/llvm-c "${OUTDIR}/include/"
    mkdir -p "${OUTDIR}/include/llvm/Config"
    cp "${BUILDDIR}"/include/llvm/Config/*.h "${OUTDIR}/include/llvm/Config/" 2>/dev/null || true
    cp "${BUILDDIR}"/include/llvm/Config/*.def "${OUTDIR}/include/llvm/Config/" 2>/dev/null || true

    XZ_OPT="-T0 -6" tar cJf "${OUTDIR}.tar.xz" "${OUTDIR}/"

    local LIB_COUNT=$(ls "${OUTDIR}"/lib/*.a | wc -l)
    local TAR_SIZE=$(du -sh "${OUTDIR}.tar.xz" | cut -f1)
    echo "  Done: ${LIB_COUNT} libs, ${TAR_SIZE} compressed"
    echo "  Output: ${OUTDIR}.tar.xz"
}

# Build selected targets
if [ "${BUILD_TARGETS}" = "all" ]; then
    for t in "${TARGETS[@]}"; do
        build_target "$t"
    done
else
    build_target "${BUILD_TARGETS}"
fi

echo ""
echo "=== Summary ==="
ls -lh llvm-${LLVM_VERSION}-*.tar.xz 2>/dev/null | awk '{print "  " $NF " (" $5 ")"}'
