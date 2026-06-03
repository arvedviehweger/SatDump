# Prebuilt iOS dependencies

The iOS build links SatDump's third-party C/C++ dependencies as **static
libraries**. They have to be cross-compiled for iOS (`arm64-ios`) ahead of
time and placed here, mirroring what the Android port does with its
`Android-Dependencies` submodule.

The iOS CMake build expects this layout:

```
ios/deps/
├── include/        Headers for all libraries below
└── lib/            Static (.a) libraries
```

Both directories are git-ignored (the binaries are large and toolchain
specific) — only this README is tracked.

## Required libraries

| Library  | Static lib            | Used for                              |
|----------|-----------------------|---------------------------------------|
| volk     | `libvolk.a`           | SIMD-accelerated DSP kernels          |
| FFTW3    | `libfftw3f.a`         | FFTs (single precision)               |
| libpng   | `libpng.a`            | PNG image I/O                         |
| zlib     | `libz.a`              | Compression (used by libpng, etc.)    |
| nng      | `libnng.a`            | Networking / messaging                |
| curl     | `libcurl.a`           | HTTP downloads (TLEs, updates)        |
| zstd     | `libzstd.a`           | ZIQ + SDR++ Server decompression      |
| libtiff  | `libtiff.a`           | TIFF image I/O                        |

`curl` should be built against Apple's Secure Transport (the iOS CMake
already links the `Security`, `CFNetwork` and `SystemConfiguration`
frameworks for it).

If `zstd` is not provided, the build still works but ZIQ support and the
SDR++ Server source plugin are disabled.

## Recommended: build with vcpkg

SatDump already uses vcpkg for the macOS build (see `../../macOS`). The same
approach works for iOS with the `arm64-ios` triplet:

```sh
git clone https://github.com/microsoft/vcpkg
./vcpkg/bootstrap-vcpkg.sh
./vcpkg/vcpkg install --triplet arm64-ios \
    volk fftw3 libpng zlib nng curl zstd tiff

# Then copy the results into ios/deps:
cp -r vcpkg/installed/arm64-ios/include ios/deps/include
cp -r vcpkg/installed/arm64-ios/lib     ios/deps/lib
```

Alternatively each library can be cross-compiled manually with the iOS SDK
(`xcrun --sdk iphoneos`) and an `arm64-apple-ios` target.
