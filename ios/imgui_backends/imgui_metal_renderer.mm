// ----------------------------------------------------------------------------
// Self-contained Dear ImGui renderer backend for Metal (iOS).
// See imgui_metal_renderer.h for the rationale (texture-handle registry).
// ----------------------------------------------------------------------------

#import "imgui_metal_renderer.h"
#import <Foundation/Foundation.h>

#include <cstdint>
#include "imgui/imgui.h"

// ----------------------------------------------------------------------------
// State
// ----------------------------------------------------------------------------

static id<MTLDevice> g_device = nil;
static id<MTLRenderPipelineState> g_pipelineState = nil;
static id<MTLSamplerState> g_samplerState = nil;
static MTLPixelFormat g_colorPixelFormat = MTLPixelFormatBGRA8Unorm;

// Texture registry. SatDump references textures by integer handle.
static NSMutableDictionary<NSNumber *, id<MTLTexture>> *g_textures = nil;
static unsigned int g_nextTextureId = 1;

// Dear ImGui font atlas texture handle.
static unsigned int g_fontTextureId = 0;

// ----------------------------------------------------------------------------
// Metal shading language source for the ImGui pass
// ----------------------------------------------------------------------------

static NSString *const kShaderSource = @R"METAL(
#include <metal_stdlib>
using namespace metal;

struct Uniforms
{
    float4x4 projectionMatrix;
};

struct VertexIn
{
    float2 position  [[attribute(0)]];
    float2 texCoords [[attribute(1)]];
    uchar4 color     [[attribute(2)]];
};

struct VertexOut
{
    float4 position [[position]];
    float2 texCoords;
    float4 color;
};

vertex VertexOut imgui_vertex(VertexIn in [[stage_in]],
                              constant Uniforms &uniforms [[buffer(1)]])
{
    VertexOut out;
    out.position  = uniforms.projectionMatrix * float4(in.position, 0.0, 1.0);
    out.texCoords = in.texCoords;
    out.color     = float4(in.color) / 255.0;
    return out;
}

fragment half4 imgui_fragment(VertexOut in [[stage_in]],
                              texture2d<half> tex [[texture(0)]],
                              sampler texSampler  [[sampler(0)]])
{
    half4 texColor = tex.sample(texSampler, in.texCoords);
    return half4(in.color) * texColor;
}
)METAL";

// ----------------------------------------------------------------------------
// Texture registry
// ----------------------------------------------------------------------------

unsigned int ImGuiMetal_RegisterTexture(id<MTLTexture> texture)
{
    @synchronized(g_textures)
    {
        unsigned int texId = g_nextTextureId++;
        if (texture != nil)
            g_textures[@(texId)] = texture;
        return texId;
    }
}

void ImGuiMetal_SetTexture(unsigned int texId, id<MTLTexture> texture)
{
    @synchronized(g_textures)
    {
        if (texture != nil)
            g_textures[@(texId)] = texture;
        else
            [g_textures removeObjectForKey:@(texId)];
    }
}

id<MTLTexture> ImGuiMetal_GetTexture(unsigned int texId)
{
    @synchronized(g_textures)
    {
        return g_textures[@(texId)];
    }
}

void ImGuiMetal_RemoveTexture(unsigned int texId)
{
    @synchronized(g_textures)
    {
        [g_textures removeObjectForKey:@(texId)];
    }
}

// ----------------------------------------------------------------------------
// Font atlas texture
// ----------------------------------------------------------------------------

void ImGuiMetal_RecreateFontTexture(void)
{
    if (g_device == nil)
        return;

    ImGuiIO &io = ImGui::GetIO();
    unsigned char *pixels = nullptr;
    int width = 0, height = 0;
    io.Fonts->GetTexDataAsRGBA32(&pixels, &width, &height);
    if (pixels == nullptr || width <= 0 || height <= 0)
        return;

    MTLTextureDescriptor *desc =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                           width:width
                                                          height:height
                                                       mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> fontTexture = [g_device newTextureWithDescriptor:desc];
    [fontTexture replaceRegion:MTLRegionMake2D(0, 0, width, height)
                   mipmapLevel:0
                     withBytes:pixels
                   bytesPerRow:(NSUInteger)width * 4];

    if (g_fontTextureId == 0)
        g_fontTextureId = ImGuiMetal_RegisterTexture(fontTexture);
    else
        ImGuiMetal_SetTexture(g_fontTextureId, fontTexture);

    io.Fonts->SetTexID((ImTextureID)(uintptr_t)g_fontTextureId);
}

// ----------------------------------------------------------------------------
// Lifecycle
// ----------------------------------------------------------------------------

bool ImGuiMetal_Init(id<MTLDevice> device, MTLPixelFormat colorPixelFormat)
{
    if (device == nil)
        return false;

    g_device = device;
    g_colorPixelFormat = colorPixelFormat;
    g_textures = [NSMutableDictionary dictionary];

    ImGuiIO &io = ImGui::GetIO();
    io.BackendRendererName = "imgui_impl_metal_satdump";
    io.BackendFlags |= ImGuiBackendFlags_RendererHasVtxOffset;

    // Compile shaders.
    NSError *error = nil;
    id<MTLLibrary> library = [g_device newLibraryWithSource:kShaderSource
                                                    options:nil
                                                      error:&error];
    if (library == nil)
    {
        NSLog(@"[ImGuiMetal] Shader compilation failed: %@", error);
        return false;
    }

    id<MTLFunction> vertexFunction = [library newFunctionWithName:@"imgui_vertex"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"imgui_fragment"];

    // Vertex layout: matches Dear ImGui's ImDrawVert { pos, uv, col }.
    MTLVertexDescriptor *vertexDescriptor = [MTLVertexDescriptor vertexDescriptor];
    vertexDescriptor.attributes[0].format = MTLVertexFormatFloat2;
    vertexDescriptor.attributes[0].offset = IM_OFFSETOF(ImDrawVert, pos);
    vertexDescriptor.attributes[0].bufferIndex = 0;
    vertexDescriptor.attributes[1].format = MTLVertexFormatFloat2;
    vertexDescriptor.attributes[1].offset = IM_OFFSETOF(ImDrawVert, uv);
    vertexDescriptor.attributes[1].bufferIndex = 0;
    vertexDescriptor.attributes[2].format = MTLVertexFormatUChar4;
    vertexDescriptor.attributes[2].offset = IM_OFFSETOF(ImDrawVert, col);
    vertexDescriptor.attributes[2].bufferIndex = 0;
    vertexDescriptor.layouts[0].stride = sizeof(ImDrawVert);
    vertexDescriptor.layouts[0].stepRate = 1;
    vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;

    // Render pipeline with standard alpha blending.
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.vertexFunction = vertexFunction;
    pipelineDescriptor.fragmentFunction = fragmentFunction;
    pipelineDescriptor.vertexDescriptor = vertexDescriptor;
    pipelineDescriptor.colorAttachments[0].pixelFormat = g_colorPixelFormat;
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    g_pipelineState = [g_device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    if (g_pipelineState == nil)
    {
        NSLog(@"[ImGuiMetal] Pipeline creation failed: %@", error);
        return false;
    }

    // Linear-filtering sampler.
    MTLSamplerDescriptor *samplerDescriptor = [[MTLSamplerDescriptor alloc] init];
    samplerDescriptor.minFilter = MTLSamplerMinMagFilterLinear;
    samplerDescriptor.magFilter = MTLSamplerMinMagFilterLinear;
    samplerDescriptor.mipFilter = MTLSamplerMipFilterLinear;
    samplerDescriptor.sAddressMode = MTLSamplerAddressModeClampToEdge;
    samplerDescriptor.tAddressMode = MTLSamplerAddressModeClampToEdge;
    g_samplerState = [g_device newSamplerStateWithDescriptor:samplerDescriptor];

    ImGuiMetal_RecreateFontTexture();
    return true;
}

void ImGuiMetal_Shutdown(void)
{
    g_pipelineState = nil;
    g_samplerState = nil;
    g_textures = nil;
    g_device = nil;
    g_fontTextureId = 0;
    g_nextTextureId = 1;
}

void ImGuiMetal_NewFrame(void)
{
    // Lazily (re)build the font atlas texture if it is missing.
    if (g_device != nil && ImGui::GetIO().Fonts->TexID == 0)
        ImGuiMetal_RecreateFontTexture();
}

// ----------------------------------------------------------------------------
// Draw data rendering
// ----------------------------------------------------------------------------

void ImGuiMetal_RenderDrawData(ImDrawData *drawData, id<MTLRenderCommandEncoder> encoder)
{
    if (drawData == nullptr || encoder == nil || g_pipelineState == nil)
        return;

    int fbWidth = (int)(drawData->DisplaySize.x * drawData->FramebufferScale.x);
    int fbHeight = (int)(drawData->DisplaySize.y * drawData->FramebufferScale.y);
    if (fbWidth <= 0 || fbHeight <= 0 || drawData->CmdListsCount == 0)
        return;

    [encoder setRenderPipelineState:g_pipelineState];
    [encoder setFragmentSamplerState:g_samplerState atIndex:0];
    [encoder setViewport:(MTLViewport){0.0, 0.0, (double)fbWidth, (double)fbHeight, 0.0, 1.0}];

    // Orthographic projection. The 16 floats below are interpreted column by
    // column by the Metal float4x4 in the shader.
    float L = drawData->DisplayPos.x;
    float R = drawData->DisplayPos.x + drawData->DisplaySize.x;
    float T = drawData->DisplayPos.y;
    float B = drawData->DisplayPos.y + drawData->DisplaySize.y;
    float projection[4][4] = {
        {2.0f / (R - L), 0.0f, 0.0f, 0.0f},
        {0.0f, 2.0f / (T - B), 0.0f, 0.0f},
        {0.0f, 0.0f, 1.0f, 0.0f},
        {(R + L) / (L - R), (T + B) / (B - T), 0.0f, 1.0f},
    };
    [encoder setVertexBytes:projection length:sizeof(projection) atIndex:1];

    ImVec2 clipOffset = drawData->DisplayPos;
    ImVec2 clipScale = drawData->FramebufferScale;
    const MTLIndexType indexType =
        sizeof(ImDrawIdx) == 2 ? MTLIndexTypeUInt16 : MTLIndexTypeUInt32;

    for (int n = 0; n < drawData->CmdListsCount; n++)
    {
        const ImDrawList *cmdList = drawData->CmdLists[n];
        if (cmdList->VtxBuffer.Size == 0 || cmdList->IdxBuffer.Size == 0)
            continue;

        id<MTLBuffer> vertexBuffer =
            [g_device newBufferWithBytes:cmdList->VtxBuffer.Data
                                  length:(NSUInteger)cmdList->VtxBuffer.Size * sizeof(ImDrawVert)
                                 options:MTLResourceStorageModeShared];
        id<MTLBuffer> indexBuffer =
            [g_device newBufferWithBytes:cmdList->IdxBuffer.Data
                                  length:(NSUInteger)cmdList->IdxBuffer.Size * sizeof(ImDrawIdx)
                                 options:MTLResourceStorageModeShared];
        [encoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];

        for (int i = 0; i < cmdList->CmdBuffer.Size; i++)
        {
            const ImDrawCmd *cmd = &cmdList->CmdBuffer[i];
            if (cmd->UserCallback != nullptr)
            {
                cmd->UserCallback(cmdList, cmd);
                continue;
            }
            if (cmd->ElemCount == 0)
                continue;

            // Project the clip rectangle into framebuffer space.
            float clipMinX = (cmd->ClipRect.x - clipOffset.x) * clipScale.x;
            float clipMinY = (cmd->ClipRect.y - clipOffset.y) * clipScale.y;
            float clipMaxX = (cmd->ClipRect.z - clipOffset.x) * clipScale.x;
            float clipMaxY = (cmd->ClipRect.w - clipOffset.y) * clipScale.y;
            if (clipMinX < 0.0f) clipMinX = 0.0f;
            if (clipMinY < 0.0f) clipMinY = 0.0f;
            if (clipMaxX > (float)fbWidth) clipMaxX = (float)fbWidth;
            if (clipMaxY > (float)fbHeight) clipMaxY = (float)fbHeight;
            if (clipMaxX <= clipMinX || clipMaxY <= clipMinY)
                continue;

            [encoder setScissorRect:(MTLScissorRect){
                                        (NSUInteger)clipMinX, (NSUInteger)clipMinY,
                                        (NSUInteger)(clipMaxX - clipMinX),
                                        (NSUInteger)(clipMaxY - clipMinY)}];

            id<MTLTexture> texture = ImGuiMetal_GetTexture((unsigned int)(uintptr_t)cmd->GetTexID());
            if (texture == nil)
                continue;
            [encoder setFragmentTexture:texture atIndex:0];

            [encoder setVertexBufferOffset:(NSUInteger)cmd->VtxOffset * sizeof(ImDrawVert) atIndex:0];
            [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                               indexCount:cmd->ElemCount
                                indexType:indexType
                              indexBuffer:indexBuffer
                        indexBufferOffset:(NSUInteger)cmd->IdxOffset * sizeof(ImDrawIdx)];
        }
    }
}
