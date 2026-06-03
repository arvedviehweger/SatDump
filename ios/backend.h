#pragma once

// iOS / Metal implementation of the SatDump backend:: abstraction
// (see src-core/core/backend.h) and of the Dear ImGui texture functions
// (see src-core/imgui/imgui_image.h).

#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

// Long-lived Metal objects. Created by AppViewController at startup.
extern id<MTLDevice> g_metalDevice;
extern id<MTLCommandQueue> g_metalCommandQueue;
extern MTKView *g_metalView;

// Per-frame Metal state, produced by funcBeginFrame() and consumed by
// funcEndFrame().
struct SatDumpMetalFrame
{
    MTLRenderPassDescriptor *renderPassDescriptor;
    id<MTLCommandBuffer> commandBuffer;
};
extern SatDumpMetalFrame g_metalFrame;

// Wires the satdump backend:: function pointers to the iOS/Metal backend.
// Must be called once, before satdump::initSatdump().
void bindBackendFunctions();

// Wires the Dear ImGui image/texture function pointers to the Metal backend.
// Must be called once, before satdump::initSatdump().
void bindImageTextureFunctions();
