# Dear ImGui Metal renderer backend

The iOS frontend renders the Dear ImGui UI with **Metal**.

Instead of the stock `imgui_impl_metal` backend, the iOS port uses a small,
**self-contained renderer** that lives here:

* `imgui_metal_renderer.h`
* `imgui_metal_renderer.mm`

## Why a custom renderer?

SatDump references textures through small `unsigned int` handles (see
`src-core/imgui/imgui_image.h`). A native Metal texture is a 64-bit object
pointer and does not fit into such a handle.

The stock `imgui_impl_metal` backend assumes `ImTextureID` *is* the
`MTLTexture`. Supporting SatDump's integer handles with the stock backend
would require either patching it or widening the texture-handle type
throughout the cross-platform SatDump code.

This in-tree renderer instead keeps an internal **texture registry** that
maps each integer handle to an `id<MTLTexture>`. That keeps all
cross-platform SatDump code untouched and removes any external dependency —
nothing needs to be downloaded to build the iOS app.

## What it does

* Compiles the ImGui vertex/fragment shaders (Metal Shading Language).
* Builds the render pipeline (alpha blending) and a linear sampler.
* Manages the Dear ImGui font atlas texture.
* Renders `ImDrawData` into a Metal render command encoder.
* Owns the integer-handle → `MTLTexture` registry used by
  `../imgui_image.mm`.

The **platform/input** side (touch, keyboard) is handled directly by
`../AppViewController.mm`.
