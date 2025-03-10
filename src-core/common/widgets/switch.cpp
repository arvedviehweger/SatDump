#include "../../imgui/imgui_internal.h"
#include "../../core/module.h"

#include "switch.h"

void ToggleButton(const char* str_id, int* v)
{
    ImVec2 p = ImGui::GetCursorScreenPos();
    ImDrawList* draw_list = ImGui::GetWindowDrawList();

    float height = ImGui::GetFrameHeight() * 0.75f;
    float width = height * 2.0f;

    ImGui::InvisibleButton(str_id, ImVec2(width, height));
    if (ImGui::IsItemClicked())
        *v = !*v;

    float t = *v ? 1.0f : 0.0f;

    ImGuiContext& g = *GImGui;
    float ANIM_SPEED = 0.04f;
    if (g.LastActiveId == g.CurrentWindow->GetID(str_id))// && g.LastActiveIdTimer < ANIM_SPEED)
    {
        float t_anim = ImSaturate(g.LastActiveIdTimer / ANIM_SPEED);
        t = *v ? (t_anim) : (1.0f - t_anim);
    }
    int off = 2;

    draw_list->AddRectFilled(p, ImVec2(p.x + width, p.y + height), IM_COL32(35, 37, 38, 255), 2);
    draw_list->AddRectFilled(ImVec2(p.x + t * height + off, p.y + off), ImVec2(p.x + (t + 1) * height - off, p.y + height - off),  IM_COL32(61, 133, 224, 255), 2);
}

void FancySlider(const char * str_id, const char * label, float* v, int width){
    ImGui::BeginGroup();
    ImVec2 p = ImGui::GetCursorScreenPos();
    ImDrawList* draw_list = ImGui::GetWindowDrawList();

    float height = ImGui::GetFrameHeight() * 0.85f;

    ImGui::SetNextItemWidth(width);
    ImGui::DragFloat(str_id, v, 100.0f/(float)width, 0, 100, "", ImGuiSliderFlags_AlwaysClamp);
    draw_list->AddRectFilled(ImVec2(p.x + 2*ui_scale, p.y + ImGui::GetFrameHeight() * 0.15f), ImVec2(p.x + *v * (width - 4*ui_scale) / 100 + 2*ui_scale, p.y + height), IM_COL32(61, 133, 224, 255), 2);
    draw_list->AddText(ImVec2(p.x + (width-ImGui::CalcTextSize(label).x)/2, p.y + ImGui::GetFrameHeight() * 0.15f), IM_COL32(255, 255, 255, 255), label);
    ImGui::EndGroup();
}