#include "tracking_widget.h"
#include "imgui/imgui.h"
#include "logger.h"
#include "core/config.h"
#include "main_ui.h"
#include "core/style.h"
#include "common/imgui_utils.h"
#include "common/tracking/rotator/rotcl_handler.h"

namespace satdump
{
    TrackingWidget::TrackingWidget()
    {
        try
        {
            qth_lon = config::main_cfg["satdump_general"]["qth_lon"]["value"].get<double>();
            qth_lat = config::main_cfg["satdump_general"]["qth_lat"]["value"].get<double>();
            qth_alt = config::main_cfg["satdump_general"]["qth_alt"]["value"].get<double>();
        }
        catch (std::exception &e)
        {
            logger->error("Could not get QTH lon/lat! %s", e.what());
        }

        logger->trace("Using QTH %f %f Alt %f", qth_lon, qth_lat, qth_alt);

        rotator_handler = std::make_shared<rotator::RotctlHandler>();

        if (rotator_handler)
        {
            try
            {
                rotator_handler->set_settings(config::main_cfg["user"]["recorder_tracking"]["rotator_config"][rotator_handler->get_id()]);
            }
            catch (std::exception &e)
            {
            }
        }

        // Init Obj Tracker
        object_tracker.setQTH(qth_lon, qth_lat, qth_alt);
        object_tracker.setRotator(rotator_handler);
        object_tracker.setObject(object_tracker.TRACKING_SATELLITE, 25338);

        // Init scheduler
        auto_scheduler.eng_callback = [this](SatellitePass, TrackedObject obj)
        {
            object_tracker.setObject(object_tracker.TRACKING_SATELLITE, obj.norad);
            saveConfig();
        };
        auto_scheduler.aos_callback = [this](SatellitePass pass, TrackedObject obj)
        {
            this->aos_callback(pass, obj);
            object_tracker.setObject(object_tracker.TRACKING_SATELLITE, obj.norad);
        };
        auto_scheduler.los_callback = [this](SatellitePass pass, TrackedObject obj)
        {
            this->los_callback(pass, obj);
        };

        auto_scheduler.setQTH(qth_lon, qth_lat, qth_alt);

        // Restore config
        loadConfig();

        // Start scheduler
        auto_scheduler.start();

        // Attempt to apply provided CLI settings
        if (satdump::config::main_cfg.contains("cli"))
        {
            auto &cli_settings = satdump::config::main_cfg["cli"];

            if (cli_settings.contains("engage_autotrack") && cli_settings["engage_autotrack"].get<bool>())
            {
                auto_scheduler.setEngaged(true, getTime());
            }
        }
    }

    TrackingWidget::~TrackingWidget()
    {
        saveConfig();
    }

    void TrackingWidget::render()
    {
        object_tracker.renderPolarPlot(light_theme);

        ImGui::Separator();

        object_tracker.renderSelectionMenu();

        ImGui::Spacing();

        if (ImGui::CollapsingHeader("Object Information"))
            object_tracker.renderObjectStatus();

        if (ImGui::CollapsingHeader("Rotator Configuration"))
        {
            object_tracker.renderRotatorStatus();
            ImGui::SameLine();

            if (rotator_handler->is_connected())
                style::beginDisabled();
            if (ImGui::Combo("Type##rotatortype", &selected_rotator_handler, "Rotctl\0"))
            {
                if (selected_rotator_handler == 0)
                {
                    rotator_handler = std::make_shared<rotator::RotctlHandler>();
                    object_tracker.setRotator(rotator_handler);
                }

                try
                {
                    rotator_handler->set_settings(config::main_cfg["user"]["recorder_tracking"]["rotator_config"][rotator_handler->get_id()]);
                }
                catch (std::exception &e)
                {
                }
            }
            if (rotator_handler->is_connected())
                style::endDisabled();

            rotator_handler->render();
        }

        ImGui::Spacing();
        ImGui::Separator();
        ImGui::Spacing();

        if (ImGui::Button("Schedule and Config"))
            config_window_was_asked = show_window_config = true;

        renderConfig();
    }

    void TrackingWidget::renderConfig()
    {
        if (show_window_config)
        {
            ImGui::Begin("Tracking Configuration", &show_window_config);
            ImGui::SetWindowSize(ImVec2(800, 550), ImGuiCond_FirstUseEver);

            if (ImGui::BeginTabBar("##trackingtabbar"))
            {
                if (ImGui::BeginTabItem("Scheduling"))
                {
                    ImGui::BeginChild("##trackingbarschedule", ImVec2(0, 0), false, ImGuiWindowFlags_NoResize);
                    auto_scheduler.renderAutotrackConfig(light_theme, getTime());
                    ImGui::EndChild();
                    ImGui::EndTabItem();
                }
                if (ImGui::BeginTabItem("Rotator Config"))
                {
                    object_tracker.renderRotatorConfig();
                    ImGui::EndTabItem();
                }
                ImGui::EndTabBar();
            }

            if (config_window_was_asked)
                ImGuiUtils_BringCurrentWindowToFront();
            config_window_was_asked = false;

            ImGui::End();
        }
    }
}
