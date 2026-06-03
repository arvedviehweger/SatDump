#pragma once

// ----------------------------------------------------------------------------
// Global iOS compatibility header.
//
// This file is force-included (clang's -include flag) into every translation
// unit of the iOS build, wired up from the top-level CMakeLists.txt. It papers
// over two classes of problems without having to edit individual source files:
//
//  1. Implicitly-declared C library functions (malloc, memcpy, printf, ...).
//     Recent clang rejects implicit function declarations as a hard error.
//     Pulling in the standard C headers up-front makes those identifiers
//     visible everywhere.
//
//  2. system(). The C library function system() is marked unavailable on iOS
//     (apps are sandboxed and cannot spawn processes). SatDump calls it in a
//     few places (Lua's os.execute, opening URLs, a couple of decoders). It is
//     redirected here to a harmless stub that returns -1, so those call sites
//     keep compiling and simply fail gracefully at runtime.
//
//     A proper fix for the URL-opening case would route through
//     -[UIApplication openURL:], but that is a separate refinement.
// ----------------------------------------------------------------------------

// (1) Standard C headers - fixes implicit-declaration errors globally.
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <math.h>

// (2) system() replacement.
#ifdef __cplusplus
extern "C"
{
#endif

// Stub for the unavailable C library system(). Always reports failure.
static inline int satdump_ios_system_stub(const char *command)
{
    (void)command;
    return -1;
}

#ifdef __cplusplus
}
#endif

// Redirect every system(...) call to the stub. Defined as a function-like
// macro so it only rewrites actual calls - never unrelated identifiers such
// as std::system_error, the <system_error> header or std::filesystem.
#define system(command) satdump_ios_system_stub(command)
