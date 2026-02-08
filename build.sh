#!/bin/bash
set -euo pipefail

LLVM_VERSION="${1:-21.1.8}"
JOBS="${2:-$(nproc)}"
SRCDIR="llvm-project-${LLVM_VERSION}.src"
TARBALL="${SRCDIR}.tar.xz"
BUILDDIR="build"
OUTDIR="llvm-${LLVM_VERSION}-mingw-x86_64-windows"

echo "=== Building LLVM ${LLVM_VERSION} for Windows (MinGW via zig cc) ==="

# Check for zig
if ! command -v zig &>/dev/null; then
    echo "ERROR: zig not found in PATH"
    exit 1
fi
echo "Using: $(zig version)"

# Create zig cc/c++ wrapper scripts
# CMake needs a single executable as the compiler, so we create thin wrappers
mkdir -p wrappers
cat > wrappers/zig-cc << 'WRAPPER'
#!/bin/bash
zig cc -target x86_64-windows-gnu -g0 "$@"
WRAPPER
cat > wrappers/zig-c++ << 'WRAPPER'
#!/bin/bash
zig c++ -target x86_64-windows-gnu -g0 "$@"
WRAPPER
chmod +x wrappers/zig-cc wrappers/zig-c++
WRAPPER_DIR="$(pwd)/wrappers"

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

# Configure
echo "Configuring..."
cmake -G Ninja -S llvm-project/llvm -B "${BUILDDIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=Windows \
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
    -DLLVM_HOST_TRIPLE=x86_64-w64-mingw32

# Build
echo "Building with ${JOBS} jobs..."
ninja -C "${BUILDDIR}" -j"${JOBS}"

# Package
echo "Packaging..."
rm -rf "${OUTDIR}"
mkdir -p "${OUTDIR}/lib" "${OUTDIR}/include"

cp "${BUILDDIR}"/lib/*.a "${OUTDIR}/lib/"
cp -r llvm-project/llvm/include/llvm-c "${OUTDIR}/include/"
mkdir -p "${OUTDIR}/include/llvm/Config"
cp "${BUILDDIR}"/include/llvm/Config/*.h "${OUTDIR}/include/llvm/Config/" 2>/dev/null || true
cp "${BUILDDIR}"/include/llvm/Config/*.def "${OUTDIR}/include/llvm/Config/" 2>/dev/null || true

tar cJf "${OUTDIR}.tar.xz" "${OUTDIR}/"

echo ""
echo "=== Done ==="
echo "Libs:    $(ls ${OUTDIR}/lib/*.a | wc -l)"
echo "Tarball: ${OUTDIR}.tar.xz ($(du -sh ${OUTDIR}.tar.xz | cut -f1))"
