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
| VOLK     | `libvolk.a`           | SIMD-accelerated DSP kernels          |
| FFTW3    | `libfftw3f.a`         | FFTs (single precision)               |
| libpng   | `libpng.a`            | PNG image I/O                         |
| zlib     | `libz.a`              | Compression (used by libpng, etc.)    |
| nng      | `libnng.a`            | Networking / messaging                |
| curl     | `libcurl.a`           | HTTP downloads (TLEs, updates)        |
| zstd     | `libzstd.a`           | ZIQ + SDR++ Server decompression      |
| libtiff  | `libtiff.a`           | TIFF image I/O                        |

If `zstd` is not provided, the build still works but ZIQ support and the
SDR++ Server source plugin are disabled.

### curl and TLS

`curl` needs a TLS backend. Two options work:

* **OpenSSL** — the vcpkg `curl` port pulls in `openssl`, producing
  `libssl.a` and `libcrypto.a`. If you copied the whole vcpkg `lib/`
  directory into `ios/deps/lib`, these are already present and the iOS
  build links them automatically (it links *every* `.a` in
  `ios/deps/lib`).
* **Apple Secure Transport** — alternatively build curl with the
  `sectransp` feature (`vcpkg install "curl[core,sectransp]"`), which uses
  the OS TLS stack and needs no OpenSSL. The iOS build already links the
  `Security`, `CFNetwork` and `SystemConfiguration` frameworks for this.

Either way, just make sure every `.a` that curl depends on ends up in
`ios/deps/lib`.

## VOLK — build it yourself (do NOT use vcpkg)

> **Important:** the `volk` package in vcpkg is the *Vulkan meta-loader*, a
> completely different project. SatDump needs **GNU Radio VOLK** (the
> "Vector-Optimized Library of Kernels"). It must be built from source.

Clone <https://github.com/gnuradio/volk> and cross-compile the static
library for iOS. VOLK's `lib/CMakeLists.txt` needs a small patch so it can
produce a static archive for iOS (force static libs, drop `pthread`
linkage, set a per-config archive output directory).

```sh
git clone --recursive https://github.com/gnuradio/volk
cd volk

cmake -B build-ios -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_SHARED_LIBS=OFF \
  -DENABLE_STATIC_LIBS=ON \
  -DENABLE_TESTING=OFF \
  -DENABLE_UTILITY_APPS=OFF \
  -DENABLE_PROFILING=OFF \
  -DENABLE_MODTOOL=OFF \
  -DENABLE_ORC=OFF \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
  -DCMAKE_INSTALL_PREFIX="$PWD/install-ios"

cmake --build build-ios --config Release --target volk_static
cmake --install build-ios --config Release
```

Then copy the result into `ios/deps`:

```sh
cp -r install-ios/include/volk   <satdump>/ios/deps/include/volk
cp install-ios/lib/libvolk.a     <satdump>/ios/deps/lib/
```

VOLK's headers are generated at build time, so `volk/volk.h` only exists
after a successful build/install — make sure `ios/deps/include/volk/volk.h`
is present, otherwise `volk_includes/volk/volk_alloc.hh` will fail to
compile.

## The remaining libraries: vcpkg

The other dependencies can come from vcpkg with the `arm64-ios` triplet:

```sh
git clone https://github.com/microsoft/vcpkg
./vcpkg/bootstrap-vcpkg.sh
./vcpkg/vcpkg install --triplet arm64-ios \
    fftw3 libpng zlib nng curl zstd tiff

# Then merge the results into ios/deps:
cp -r vcpkg/installed/arm64-ios/include/* ios/deps/include/
cp -r vcpkg/installed/arm64-ios/lib/*     ios/deps/lib/
```

Alternatively each library can be cross-compiled manually with the iOS SDK
(`xcrun --sdk iphoneos`) and an `arm64-apple-ios` target.
