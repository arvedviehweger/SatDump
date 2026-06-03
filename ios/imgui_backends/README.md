# Dear ImGui Metal backend

The iOS frontend renders the Dear ImGui UI with **Metal**.

SatDump vendors Dear ImGui itself under `src-core/imgui`, but not the
optional renderer backends. The Metal renderer backend is a stock,
unmodified Dear ImGui file, so instead of duplicating it in this repository
it is fetched on demand:

```sh
./fetch_imgui_backends.sh
```

This downloads, into this directory:

* `imgui_impl_metal.h`
* `imgui_impl_metal.mm`

at the Dear ImGui version that matches the bundled copy (currently `v1.90` —
see `IMGUI_VERSION` in `src-core/imgui/imgui.h`).

Both fetched files are git-ignored. The iOS `CMakeLists.txt` picks them up
automatically once present.

> The **platform/input** side (touch, keyboard) is handled directly by
> `AppViewController.mm`, so the `imgui_impl_osx` backend is intentionally
> not used.
