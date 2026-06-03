cmake_minimum_required(VERSION 3.13)

# Container for the iOS-only SDR source plugins. Each subdirectory builds a
# regular SatDump plugin static library; ios/CMakeLists.txt collects them
# and force-loads them into the SatDump app target the same way the regular
# plugins under plugins/ are handled.

if(NOT SATDUMP_IOS)
    return()
endif()

add_subdirectory(rtlsdr)
