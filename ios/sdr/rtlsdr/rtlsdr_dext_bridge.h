//
//  rtlsdr_dext_bridge.h
//
//  Thin C wrapper around the IOKit user-client API used to talk to the
//  RTL-SDR DriverKit extension (which lives in the separate RTL-SDR Host
//  app). Keeping this layer plain C means it compiles into satdump_core's
//  iOS plugin without any Swift/ObjC++ machinery, and can be reused by
//  other iOS clients later.
//
//  Adapted from the RTL-SDR Host project (RTLSDRBridge.{h,c}).
//

#ifndef SATDUMP_RTLSDR_DEXT_BRIDGE_H
#define SATDUMP_RTLSDR_DEXT_BRIDGE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Returns 1 if the RTL-SDR dext currently advertises at least one matching
/// IOService. Does NOT open a user-client (so it does not interfere with the
/// RTL-SDR Host app when it is itself streaming). Use this for source
/// enumeration.
int satdump_rtlsdr_dext_is_available(void);

/// Finds the RTL_SDR service and opens a user-client connection to it.
/// Returns a non-zero connection handle on success, 0 on failure. The
/// underlying user-client is exclusive; opening fails if the RTL-SDR Host
/// (or any other client) is already connected.
uint32_t satdump_rtlsdr_dext_open(void);

/// Closes a connection opened with satdump_rtlsdr_dext_open().
void satdump_rtlsdr_dext_close(uint32_t connection);

/// Invokes a scalar external method (one input value, one output value).
/// `selector` is one of the kRTLSDRMethod* constants. Returns the IOKit
/// kern_return_t (0 == KERN_SUCCESS). Any scalar result is stored in *out
/// (may be NULL if the method does not produce a scalar output).
int satdump_rtlsdr_dext_call(uint32_t connection, uint32_t selector,
                             uint64_t arg, uint64_t *out);

/// Invokes a structure-output external method (used for GetDeviceInfo).
/// `outStruct` receives up to *outSize bytes; *outSize is updated to the
/// number of bytes actually returned. Returns the IOKit kern_return_t.
int satdump_rtlsdr_dext_get_struct(uint32_t connection, uint32_t selector,
                                   void *outStruct, size_t *outSize);

/// Maps a shared memory region (memory type kRTLSDRMemoryType*) into this
/// process. Returns the mapped address, or NULL on failure; the byte size
/// is written to *outSize.
void *satdump_rtlsdr_dext_map_memory(uint32_t connection, uint32_t memoryType,
                                     uint64_t *outSize);

/// Unmaps a region previously mapped with satdump_rtlsdr_dext_map_memory().
void satdump_rtlsdr_dext_unmap_memory(uint32_t connection, uint32_t memoryType,
                                      void *address);

#ifdef __cplusplus
}
#endif

#endif /* SATDUMP_RTLSDR_DEXT_BRIDGE_H */
