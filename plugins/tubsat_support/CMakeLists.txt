cmake_minimum_required(VERSION 3.12)
project(tubsat_support)


file(GLOB_RECURSE tubsat_support_CPPS *.cpp)
add_library(tubsat_support ${SATDUMP_LIBRARY_TYPE} ${tubsat_support_CPPS})
target_link_libraries(tubsat_support PUBLIC satdump_core)
target_include_directories(tubsat_support PUBLIC src)

install(TARGETS tubsat_support DESTINATION ${CMAKE_INSTALL_LIBDIR}/satdump/plugins)