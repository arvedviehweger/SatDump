#!/usr/bin/env bash
#
# Fetches the stock Dear ImGui Metal renderer backend.
#
# SatDump vendors Dear ImGui itself in src-core/imgui, but not the optional
# platform/renderer backends. The iOS port needs the Metal renderer backend;
# this script downloads the version matching the bundled Dear ImGui.
#
# The bundled Dear ImGui version is 1.90 (see src-core/imgui/imgui.h,
# IMGUI_VERSION). Keep IMGUI_TAG below in sync if Dear ImGui is updated.
#
set -euo pipefail

IMGUI_TAG="v1.90"
BASE_URL="https://raw.githubusercontent.com/ocornut/imgui/${IMGUI_TAG}/backends"
DEST_DIR="$(cd "$(dirname "$0")" && pwd)"

FILES=(
    imgui_impl_metal.h
    imgui_impl_metal.mm
)

echo "Fetching Dear ImGui Metal backend (${IMGUI_TAG}) ..."
for f in "${FILES[@]}"; do
    echo "  - $f"
    curl -fsSL "${BASE_URL}/${f}" -o "${DEST_DIR}/${f}"
done

echo "Done. Backend files written to: ${DEST_DIR}"
