# llvm-zig

LLVM static libraries cross-compiled for all platforms using `zig cc`.

All libraries use libc++ ABI, making them compatible with Zig's linker. No system LLVM installation or platform-specific toolchains required.

## Supported targets

| Target | Zig triple | Output |
|---|---|---|
| Linux x86_64 | `x86_64-linux-gnu` | `llvm-21.1.8-x86_64-linux.tar.xz` |
| Linux aarch64 | `aarch64-linux-gnu` | `llvm-21.1.8-aarch64-linux.tar.xz` |
| Windows x86_64 | `x86_64-windows-gnu` | `llvm-21.1.8-x86_64-windows.tar.xz` |
| Windows aarch64 | `aarch64-windows-gnu` | `llvm-21.1.8-aarch64-windows.tar.xz` |
| macOS aarch64 | `aarch64-macos` | `llvm-21.1.8-aarch64-macos.tar.xz` |

## Building

Prerequisites: `zig`, `cmake`, `ninja`, `llvm-ar`, `llvm-ranlib`, `wget`

```bash
./build.sh                          # build all targets
./build.sh 21.1.8 16                # build all with 16 jobs
./build.sh 21.1.8 16 x86_64-linux-gnu  # build single target
```

## Details

- Compiler: `zig cc -target <triple> -g0`
- LLVM backends: X86 only
- Optional deps disabled: zlib, zstd, terminfo, libxml2
- Output format: `.a` archives with libc++ / Itanium ABI
- No system dependencies beyond libc at runtime
