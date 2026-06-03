# RTL-SDR (DriverKit) — iOS source plugin

This folder is an **iOS-only SatDump source plugin** that talks to an
RTL2832U-based dongle via a USBDriverKit DriverExtension. iOS does not
allow direct libusb access, so the dext takes that role; SatDump connects
to it over IOKit and reads IQ samples from a shared-memory ring buffer.

## How it fits together

```
  +------------------+        +----------------+        +--------+
  |  RTL-SDR Host    | shippt |    RTL_SDR     |   USB  | RTL-SDR|
  |  (carrier app)   +------->+  (DriverKit    +------->+ dongle |
  |                  | install|   extension)   |        |        |
  +------------------+        +-------+--------+        +--------+
                                      ^
                                      | IOKit user-client
                                      | (shared IQ ring + scalar methods)
                                      |
                              +-------+--------+
                              |    SatDump     |
                              | (this plugin)  |
                              +----------------+
```

The dext lives in the separate **RTL-SDR Host** app and stays installed and
loaded as long as that app has been launched at least once. The dext's
entitlement
`com.apple.developer.driverkit.allow-third-party-userclients = true`
lets any signed app open a user client on the dext, not just its host.

## Wire contract

`RTLSDRShared.h` is a byte-for-byte copy of the dext's own shared header. It
declares:

* **17 external method selectors** (`kRTLSDRMethodStartStream`,
  `kRTLSDRMethodSetCenterFreq`, …) — one for each librtlsdr-style control
  operation.
* **`RTLSDRRingBuffer`** — a 2 MiB shared-memory ring with free-running
  `writeCount`/`readCount` byte counters, mapped via `IOConnectMapMemory64`.
* **`RTLSDRDeviceInfo`** — returned by `kRTLSDRMethodGetDeviceInfo`.

## Files

| File                       | Purpose                                              |
|----------------------------|------------------------------------------------------|
| `RTLSDRShared.h`           | Wire contract shared with the dext (do NOT modify)   |
| `rtlsdr_dext_bridge.{h,c}` | Plain-C IOKit wrapper (open/call/map)                |
| `rtlsdr_dext_source.{h,cpp}` | SatDump `DSPSampleSource` implementation           |
| `main.cpp`                 | `PLUGIN_LOADER(...)` glue (registers the source)     |
| `CMakeLists.txt`           | Builds the static plugin library                     |

## Requirements

* **Device:** iPadOS 16+. USBDriverKit does not exist on iPhone.
* **App entitlements** (`ios/SatDump.entitlements`):
  ```xml
  <key>com.apple.developer.driverkit.communicates-with-drivers</key>
  <true/>
  ```
* **Provisioning profile:** the same Apple Developer team that holds the
  granted DriverKit entitlement for the RTL-SDR Host bundle ID must also
  grant it to SatDump's bundle ID (DriverKit access is per-team but has to
  be enabled per App ID on developer.apple.com).
* **RTL-SDR Host must be installed and have been launched at least once**
  on the device, so the system extension is activated.

## Caveats

* The dext's user client is **exclusive**. While RTL-SDR Host is itself
  streaming (its `RTLTCPServer` is running and tuned in), SatDump cannot
  open the dext in parallel — `IOServiceOpen` will fail. In that case the
  cleaner path is for SatDump to connect to RTL-SDR Host's local
  `rtl_tcp` server using the standard `RTL-TCP` SatDump source.
* Currently only the RTL2832U + R820T pairing (vendor `0x0BDA`, product
  `0x2838`) is matched. Adapting to other RTL chips means extending the
  dext's `Info.plist` matching personalities, not this plugin.
