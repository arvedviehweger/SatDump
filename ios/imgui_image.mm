// iOS / Metal implementation of the Dear ImGui texture functions
// (see src-core/imgui/imgui_image.h).
//
// SatDump uploads RGBA8 image data through these callbacks. Each texture is
// stored in the renderer's texture registry and referenced by an integer
// handle (see imgui_backends/imgui_metal_renderer.h).

#import "backend.h"
#import "imgui_backends/imgui_metal_renderer.h"
#import <Metal/Metal.h>

#include "imgui/imgui_image.h"

// Creates an RGBA8 Metal texture from a tightly packed RGBA buffer.
static id<MTLTexture> createTextureRGBA(uint32_t *buffer, int width, int height, bool mipmapped)
{
    if (g_metalDevice == nil || buffer == nullptr || width <= 0 || height <= 0)
        return nil;

    MTLTextureDescriptor *descriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                           width:(NSUInteger)width
                                                          height:(NSUInteger)height
                                                       mipmapped:(mipmapped ? YES : NO)];
    descriptor.usage = MTLTextureUsageShaderRead;

    id<MTLTexture> texture = [g_metalDevice newTextureWithDescriptor:descriptor];
    if (texture == nil)
        return nil;

    [texture replaceRegion:MTLRegionMake2D(0, 0, width, height)
               mipmapLevel:0
                 withBytes:buffer
               bytesPerRow:(NSUInteger)width * 4];

    if (mipmapped && texture.mipmapLevelCount > 1 && g_metalCommandQueue != nil)
    {
        id<MTLCommandBuffer> commandBuffer = [g_metalCommandQueue commandBuffer];
        id<MTLBlitCommandEncoder> blit = [commandBuffer blitCommandEncoder];
        [blit generateMipmapsForTexture:texture];
        [blit endEncoding];
        [commandBuffer commit];
    }

    return texture;
}

static unsigned int funcMakeImageTexture()
{
    // Reserve a handle. The actual texture is created on the first update.
    return ImGuiMetal_RegisterTexture(nil);
}

static void funcUpdateImageTexture(unsigned int texId, uint32_t *buffer, int width, int height)
{
    @autoreleasepool
    {
        id<MTLTexture> texture = createTextureRGBA(buffer, width, height, false);
        if (texture != nil)
            ImGuiMetal_SetTexture(texId, texture);
    }
}

static void funcUpdateMMImageTexture(unsigned int texId, uint32_t *buffer, int width, int height)
{
    @autoreleasepool
    {
        id<MTLTexture> texture = createTextureRGBA(buffer, width, height, true);
        if (texture != nil)
            ImGuiMetal_SetTexture(texId, texture);
    }
}

static void funcDeleteImageTexture(unsigned int texId)
{
    ImGuiMetal_RemoveTexture(texId);
}

void bindImageTextureFunctions()
{
    // Conservative limit valid for every Metal-capable iOS device.
    maxTextureSize = 8192;

    makeImageTexture = funcMakeImageTexture;
    updateImageTexture = funcUpdateImageTexture;
    updateMMImageTexture = funcUpdateMMImageTexture;
    deleteImageTexture = funcDeleteImageTexture;
}
