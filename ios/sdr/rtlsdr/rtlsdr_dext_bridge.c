//
//  rtlsdr_dext_bridge.c
//
//  IOKit user-client glue. See rtlsdr_dext_bridge.h.
//

#include "rtlsdr_dext_bridge.h"

#include <IOKit/IOKitLib.h>
#include <mach/mach.h>

/* The dext's interface driver is registered under its IOUserClass name.
 * Matching by name is exact, so this does not pick up "RTL_SDR_DEV"
 * (the device-level driver) - we want the interface driver that owns the
 * user client. */
static const char *kRTLSDRServiceName = "RTL_SDR";

int satdump_rtlsdr_dext_is_available(void)
{
    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t kr = IOServiceGetMatchingServices(
        0, IOServiceNameMatching(kRTLSDRServiceName), &iterator);
    if (kr != KERN_SUCCESS)
        return 0;

    int found = 0;
    io_service_t service;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL)
    {
        ++found;
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return found > 0 ? 1 : 0;
}

uint32_t satdump_rtlsdr_dext_open(void)
{
    /* Passing 0 as the main port selects the default IOKit main port; this
     * avoids depending on kIOMainPortDefault vs kIOMasterPortDefault naming. */
    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t kr = IOServiceGetMatchingServices(
        0, IOServiceNameMatching(kRTLSDRServiceName), &iterator);
    if (kr != KERN_SUCCESS)
        return 0;

    io_connect_t connection = IO_OBJECT_NULL;
    io_service_t service;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL)
    {
        kr = IOServiceOpen(service, mach_task_self_, 0, &connection);
        IOObjectRelease(service);
        if (kr == KERN_SUCCESS)
            break;
        connection = IO_OBJECT_NULL;
    }
    IOObjectRelease(iterator);

    return (uint32_t)connection;
}

void satdump_rtlsdr_dext_close(uint32_t connection)
{
    if (connection != IO_OBJECT_NULL)
        IOServiceClose((io_connect_t)connection);
}

int satdump_rtlsdr_dext_call(uint32_t connection, uint32_t selector,
                             uint64_t arg, uint64_t *out)
{
    uint64_t input[1]  = { arg };
    uint64_t output[1] = { 0 };
    uint32_t outputCount = 1;

    kern_return_t kr = IOConnectCallScalarMethod(
        (io_connect_t)connection, selector,
        input, 1, output, &outputCount);

    if (out != NULL)
        *out = (outputCount > 0) ? output[0] : 0;
    return (int)kr;
}

int satdump_rtlsdr_dext_get_struct(uint32_t connection, uint32_t selector,
                                   void *outStruct, size_t *outSize)
{
    kern_return_t kr = IOConnectCallStructMethod(
        (io_connect_t)connection, selector,
        NULL, 0, outStruct, outSize);
    return (int)kr;
}

void *satdump_rtlsdr_dext_map_memory(uint32_t connection, uint32_t memoryType,
                                     uint64_t *outSize)
{
    mach_vm_address_t address = 0;
    mach_vm_size_t    size    = 0;

    kern_return_t kr = IOConnectMapMemory64(
        (io_connect_t)connection, memoryType,
        mach_task_self_, &address, &size, kIOMapAnywhere);
    if (kr != KERN_SUCCESS)
        return NULL;

    if (outSize != NULL)
        *outSize = (uint64_t)size;
    return (void *)(uintptr_t)address;
}

void satdump_rtlsdr_dext_unmap_memory(uint32_t connection, uint32_t memoryType,
                                      void *address)
{
    if (connection == IO_OBJECT_NULL || address == NULL)
        return;
    IOConnectUnmapMemory64((io_connect_t)connection, memoryType,
                           mach_task_self_, (mach_vm_address_t)(uintptr_t)address);
}
