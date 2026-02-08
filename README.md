# llvm-windows-zig

LLVM static libraries cross-compiled for Windows x86_64 using `zig cc`.

These libraries use the MinGW/libc++ ABI, making them compatible with Zig's linker (`linkLibC()` + `linkLibCpp()`). The official LLVM Windows release uses MSVC ABI which is incompatible with Zig.

## Why?

The official LLVM Windows release (`clang+llvm-*-x86_64-pc-windows-msvc.tar.xz`) is built with MSVC (`/MT`). The resulting `.lib` files:

- Embed `/DEFAULTLIB:libcmt` directives that conflict with Zig's MinGW CRT
- Use MSVC C++ ABI (`operator new`, `_Mtx_lock`, `__security_cookie`, etc.) which is incompatible with Zig's bundled libc++
- Cannot be used with Zig's `linkLibC()` or `linkLibCpp()`

This repo builds LLVM from source targeting MinGW via `zig cc`, producing `.a` files with libc++ ABI that work with Zig out of the box.

## Building

Prerequisites: `zig`, `cmake`, `ninja`, `llvm-ar`, `llvm-ranlib`, `wget`

```bash
./build.sh 21.1.8       # build LLVM 21.1.8
./build.sh 21.1.8 16    # build with 16 jobs
```

Output: `llvm-21.1.8-mingw-x86_64-windows.tar.xz` containing `lib/*.a` and `include/` headers.

## Usage with Zig

The repackaged tarball from [zgram-llvm](https://github.com/dzonerzy/zgram-llvm) consumes these libraries. In `build.zig`:

```zig
exe.root_module.linkSystemLibrary("psapi", .{});
exe.root_module.linkSystemLibrary("ole32", .{});
exe.root_module.linkSystemLibrary("oleaut32", .{});
exe.root_module.linkSystemLibrary("advapi32", .{});
exe.root_module.linkSystemLibrary("shell32", .{});
exe.root_module.linkSystemLibrary("shlwapi", .{});
exe.root_module.linkSystemLibrary("uuid", .{});
exe.root_module.linkSystemLibrary("user32", .{});
exe.linkLibC();
exe.linkLibCpp();
```

## Details

- Compiler: `zig cc -target x86_64-windows-gnu`
- LLVM backends: X86 only
- Optional deps disabled: zlib, zstd, terminfo, libxml2
- Output format: MinGW `.a` archives (COFF objects, Itanium ABI)
- C++ stdlib: libc++ (via zig cc)
