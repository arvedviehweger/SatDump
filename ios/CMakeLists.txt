cmake_minimum_required(VERSION 3.13)

# ----------------------------------------------------------------------------
# SatDump iOS application bundle
#
# This file is added by the top-level CMakeLists.txt when building for iOS
# (SATDUMP_IOS). It defines the SatDump.app bundle and links satdump_core,
# satdump_interface and every plugin statically into it.
# ----------------------------------------------------------------------------

if(NOT SATDUMP_IOS)
    return()
endif()

# The application sources are Objective-C++ (Metal / UIKit glue).
enable_language(OBJCXX)
set(CMAKE_OBJCXX_STANDARD 17)
set(CMAKE_OBJCXX_STANDARD_REQUIRED ON)

set(SATDUMP_IOS_SOURCES
    main.mm
    AppViewController.mm
    backend.mm
    imgui_image.mm
    imgui_backends/imgui_metal_renderer.mm
)

# Files copied into the application bundle (read by the app at runtime).
set(SATDUMP_BUNDLE_FILES
    "${CMAKE_SOURCE_DIR}/satdump_cfg.json"
    "${CMAKE_SOURCE_DIR}/icon.png"
    "${CMAKE_SOURCE_DIR}/resources"
    "${CMAKE_SOURCE_DIR}/pipelines"
)

add_executable(SatDump MACOSX_BUNDLE ${SATDUMP_IOS_SOURCES} ${SATDUMP_BUNDLE_FILES})

target_include_directories(SatDump PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/src-core
    ${CMAKE_SOURCE_DIR}/src-interface
    ${CMAKE_SOURCE_DIR}/ios/deps/include
)

# Prebuilt iOS dependencies (also added globally in the top-level
# CMakeLists.txt; repeated here so the application target links them directly).
target_link_directories(SatDump PRIVATE
    ${CMAKE_SOURCE_DIR}/ios/deps/lib
)

# Bundle the runtime data. It is added to the target so Xcode copies (and
# signs) it as part of the normal "Copy Bundle Resources" phase.
set_source_files_properties(${SATDUMP_BUNDLE_FILES} PROPERTIES
    MACOSX_PACKAGE_LOCATION "Resources")

# Bundle metadata and Xcode settings.
set_target_properties(SatDump PROPERTIES
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist"
    XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC YES
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "org.satdump.SatDump"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
)

# ----------------------------------------------------------------------------
# Linking
#
# Everything is static. Plugins (and SatDump's own libraries) rely on static
# initializers for self-registration - the plugin registry, module/pipeline
# registration, etc. A normal static link would drop the object files that
# are not otherwise referenced, so every archive is force-loaded.
# ----------------------------------------------------------------------------

target_link_libraries(SatDump PRIVATE satdump_core satdump_interface)

target_link_options(SatDump PRIVATE
    "-Wl,-force_load,$<TARGET_FILE:satdump_core>"
    "-Wl,-force_load,$<TARGET_FILE:satdump_interface>"
)

# Recursively collect every target defined under plugins/.
function(satdump_collect_targets out_var dir)
    get_property(subdirs DIRECTORY "${dir}" PROPERTY SUBDIRECTORIES)
    foreach(subdir ${subdirs})
        satdump_collect_targets(${out_var} "${subdir}")
    endforeach()
    get_property(dir_targets DIRECTORY "${dir}" PROPERTY BUILDSYSTEM_TARGETS)
    set(${out_var} ${${out_var}} ${dir_targets} PARENT_SCOPE)
endfunction()

satdump_collect_targets(SATDUMP_PLUGIN_TARGETS "${CMAKE_SOURCE_DIR}/plugins")

foreach(plugin_target ${SATDUMP_PLUGIN_TARGETS})
    get_target_property(target_type ${plugin_target} TYPE)
    if(target_type STREQUAL "STATIC_LIBRARY")
        message("iOS: linking plugin ${plugin_target}")
        add_dependencies(SatDump ${plugin_target})
        target_link_options(SatDump PRIVATE
            "-Wl,-force_load,$<TARGET_FILE:${plugin_target}>")
    endif()
endforeach()

# iOS system frameworks.
target_link_libraries(SatDump PRIVATE
    "-framework Metal"
    "-framework MetalKit"
    "-framework UIKit"
    "-framework Foundation"
    "-framework QuartzCore"
    "-framework CoreGraphics"
    "-framework Security"
    "-framework CFNetwork"
    "-framework SystemConfiguration"
)
