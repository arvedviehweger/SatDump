#pragma once

// ----------------------------------------------------------------------------
// Self-contained Dear ImGui renderer backend for Metal (iOS).
//
// SatDump references textures through small unsigned-int handles (see
// src-core/imgui/imgui_image.h). A native Metal texture is a 64-bit object
// pointer and does not fit into that handle, so this renderer keeps an
// internal registry mapping each integer handle to an id<MTLTexture>.
//
// Because of that registry this backend is intentionally NOT the stock
// Dear ImGui imgui_impl_metal backend: keeping it in-tree avoids touching
// any cross-platform SatDump code and removes an external dependency.
// ----------------------------------------------------------------------------

#import <Metal/Metal.h>

struct ImDrawData;

#ifdef __cplusplus
extern "C"
{
#endif

    // Renderer lifecycle ------------------------------------------------------

    // Initializes the renderer (shaders, pipeline, default font texture).
    // colorPixelFormat must match the MTKView's colorPixelFormat.
    bool ImGuiMetal_Init(id<MTLDevice> device, MTLPixelFormat colorPixelFormat);

    // Releases all renderer resources.
    void ImGuiMetal_Shutdown(void);

    // Called once per frame before ImGui::NewFrame(). Ensures the font
    // texture exists.
    void ImGuiMetal_NewFrame(void);

    // Records the ImGui draw data into the given command buffer/encoder pair.
    void ImGuiMetal_RenderDrawData(struct ImDrawData *drawData,
                                   id<MTLCommandBuffer> commandBuffer,
                                   id<MTLRenderCommandEncoder> encoder);

    // Rebuilds the Dear ImGui font atlas texture (used by backend::rebuildFonts).
    void ImGuiMetal_RecreateFontTexture(void);

    // Texture registry --------------------------------------------------------

    // Registers a texture and returns a new integer handle. The texture may
    // be nil; in that case the handle is reserved and a texture can be bound
    // to it later with ImGuiMetal_SetTexture().
    unsigned int ImGuiMetal_RegisterTexture(id<MTLTexture> texture);

    // Binds (or replaces) the texture for an existing handle. Passing nil
    // removes the entry.
    void ImGuiMetal_SetTexture(unsigned int texId, id<MTLTexture> texture);

    // Returns the texture bound to a handle, or nil.
    id<MTLTexture> ImGuiMetal_GetTexture(unsigned int texId);

    // Removes a texture handle from the registry.
    void ImGuiMetal_RemoveTexture(unsigned int texId);

#ifdef __cplusplus
}
#endif
