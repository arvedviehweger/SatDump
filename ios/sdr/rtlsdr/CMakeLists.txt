cmake_minimum_required(VERSION 3.13)
project(rtlsdr_dext_support)

# iOS-only plugin that talks to an RTL-SDR via the USBDriverKit extension
# shipped in the separate RTL-SDR Host app.
if(NOT SATDUMP_IOS)
    return()
endif()

file(GLOB_RECURSE rtlsdr_dext_support_SRCS *.cpp *.c)

add_library(rtlsdr_dext_support ${SATDUMP_LIBRARY_TYPE} ${rtlsdr_dext_support_SRCS})
target_include_directories(rtlsdr_dext_support PUBLIC .)
target_link_libraries(rtlsdr_dext_support PUBLIC satdump_core)

# IOKit is needed by rtlsdr_dext_bridge.c; the framework itself is linked
# once by the final SatDump app target (see ios/CMakeLists.txt).
