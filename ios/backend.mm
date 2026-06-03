// iOS / Metal implementation of the SatDump backend:: abstraction.

#import "backend.h"
#import "imgui_backends/imgui_metal_renderer.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#include <utility>
#include "imgui/imgui.h"
#include "core/backend.h"
#include "core/style.h"

// Metal globals (declared in backend.h).
id<MTLDevice> g_metalDevice = nil;
id<MTLCommandQueue> g_metalCommandQueue = nil;
MTKView *g_metalView = nil;
SatDumpMetalFrame g_metalFrame = {nil, nil};

// Timestamp of the previous frame, for ImGuiIO::DeltaTime.
static double g_lastFrameTime = 0.0;

// ----------------------------------------------------------------------------
// backend:: callbacks
// ----------------------------------------------------------------------------

static float funcDeviceScale()
{
    float scale = (float)[UIScreen mainScreen].scale;
    return scale > 0.0f ? scale : 1.0f;
}

static void funcRebuildFonts()
{
    ImGuiMetal_RecreateFontTexture();
}

static void funcSetMousePos(int, int)
{
    // Not applicable with touch input on iOS.
}

static std::pair<int, int> funcBeginFrame()
{
    // Acquire the per-frame Metal objects.
    g_metalFrame.renderPassDescriptor = g_metalView.currentRenderPassDescriptor;
    g_metalFrame.commandBuffer = [g_metalCommandQueue commandBuffer];

    ImGuiMetal_NewFrame();

    ImGuiIO &io = ImGui::GetIO();

    // Dear ImGui works in framebuffer pixels here (DisplayFramebufferScale 1).
    CGSize drawableSize = g_metalView.drawableSize;
    if (drawableSize.width < 1.0)
        drawableSize.width = 1.0;
    if (drawableSize.height < 1.0)
        drawableSize.height = 1.0;
    io.DisplaySize = ImVec2((float)drawableSize.width, (float)drawableSize.height);
    io.DisplayFramebufferScale = ImVec2(1.0f, 1.0f);

    double now = CACurrentMediaTime();
    io.DeltaTime = (g_lastFrameTime > 0.0) ? (float)(now - g_lastFrameTime) : (1.0f / 60.0f);
    if (io.DeltaTime <= 0.0f)
        io.DeltaTime = 1.0f / 60.0f;
    g_lastFrameTime = now;

    ImGui::NewFrame();
    return {(int)drawableSize.width, (int)drawableSize.height};
}

static void funcEndFrame()
{
    ImGui::Render();

    MTLRenderPassDescriptor *renderPassDescriptor = g_metalFrame.renderPassDescriptor;
    id<MTLCommandBuffer> commandBuffer = g_metalFrame.commandBuffer;

    if (renderPassDescriptor != nil && commandBuffer != nil)
    {
        renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        renderPassDescriptor.colorAttachments[0].clearColor =
            MTLClearColorMake(style::theme.frame_bg.Value.x,
                              style::theme.frame_bg.Value.y,
                              style::theme.frame_bg.Value.z, 1.0);

        id<MTLRenderCommandEncoder> encoder =
            [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        ImGuiMetal_RenderDrawData(ImGui::GetDrawData(), commandBuffer, encoder);
        [encoder endEncoding];

        id<CAMetalDrawable> drawable = g_metalView.currentDrawable;
        if (drawable != nil)
            [commandBuffer presentDrawable:drawable];
    }

    if (commandBuffer != nil)
        [commandBuffer commit];

    g_metalFrame.renderPassDescriptor = nil;
    g_metalFrame.commandBuffer = nil;
}

static void funcSetIcon(uint8_t *, int, int)
{
    // iOS applications cannot change their icon at runtime.
}

void bindBackendFunctions()
{
    backend::device_scale = funcDeviceScale();

    backend::rebuildFonts = funcRebuildFonts;
    backend::setMousePos = funcSetMousePos;
    backend::beginFrame = funcBeginFrame;
    backend::endFrame = funcEndFrame;
    backend::setIcon = funcSetIcon;
}
