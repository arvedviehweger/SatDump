# SatDump for iOS

This directory contains the **iOS port** of SatDump.

It is modelled after the existing Android port (`../android`), but adapted to
the constraints of iOS:

* **No USB SDRs.** iOS provides no USB host access, so every USB-based SDR
  source plugin is disabled. Only the **network SDR sources** are supported:
  `net_source`, `RTL-TCP`, `SpyServer` and `SDR++ Server`.
* **Static linking.** iOS does not allow loading arbitrary dynamic libraries
  at runtime, so `satdump_core`, `satdump_interface` and every plugin are
  built as **static archives** and linked into a single application bundle.
  Plugins register themselves through a static plugin registry instead of
  being `dlopen()`-ed (see `src-core/core/plugin.h`).
* **Metal rendering.** The desktop GLFW/OpenGL frontend is replaced by a
  Metal + UIKit frontend that drives the same Dear ImGui based UI.

> **Status: experimental.** This is a work-in-progress port. It sets up the
> complete build system, application shell and rendering backend. Building it
> requires a Mac with Xcode and a set of cross-compiled dependencies (see
> below).

## Layout

```
ios/
├── CMakeLists.txt        iOS application bundle target
├── Info.plist            iOS bundle metadata
├── main.mm               UIApplicationMain entry point + AppDelegate
├── AppViewController.*   MTKView based view controller + ImGui loop
├── backend.mm/.h         SatDump backend:: implementation (Metal)
├── imgui_image.mm        Dear ImGui texture bridge (Metal)
├── imgui_backends/       Dear ImGui Metal renderer backend (fetched)
├── deps/                 Prebuilt cross-compiled dependencies
└── build.sh              Convenience script: generate the Xcode project
```

## Building

### Requirements

* macOS with **Xcode** (14 or newer) and the iOS SDK
* **CMake** 3.20 or newer
* An Apple developer signing identity (for running on a device)

### 1. Provide the prebuilt dependencies

SatDump depends on several C/C++ libraries (volk, fftw3, libpng, zlib, nng,
curl, zstd, tiff). These must be cross-compiled for `arm64-ios` and placed
under `ios/deps`. See [`deps/README.md`](deps/README.md) for the exact list
and the recommended way to build them (vcpkg with an `arm64-ios` triplet).

### 2. Fetch the Dear ImGui Metal backend

The Metal renderer backend is a stock Dear ImGui file and is **not** vendored
in this repository. Fetch the version matching the bundled ImGui:

```sh
cd ios
./imgui_backends/fetch_imgui_backends.sh
```

### 3. Generate the Xcode project

```sh
cd ios
./build.sh          # wraps the cmake invocation below
```

or manually, from the repository root:

```sh
cmake -B build-ios -G Xcode \
      -DCMAKE_SYSTEM_NAME=iOS \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
      -DCMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH=NO
```

### 4. Build and run

Open `build-ios/SatDump.xcodeproj` in Xcode, select the `SatDump` scheme and
a device, set your signing team, then build and run.

## Notes / known limitations

* Audio output (PortAudio sink) is disabled for now.
* The `remote_sdr` plugin is disabled because it also builds a standalone
  server executable, which cannot live inside an iOS app bundle.
* Local network access (for RTL-TCP / SpyServer servers on your LAN)
  triggers the iOS "Local Network" privacy prompt the first time it is used.
