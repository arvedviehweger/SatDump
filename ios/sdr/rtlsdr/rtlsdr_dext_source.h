//
//  rtlsdr_dext_source.h
//
//  SatDump DSPSampleSource implementation that talks to the RTL-SDR
//  USBDriverKit extension shipped inside the separate RTL-SDR Host app
//  (iOS-only). Uses the IOKit C bridge in rtlsdr_dext_bridge.h and the
//  shared wire contract in RTLSDRShared.h.
//

#pragma once

#include "common/dsp_source_sink/dsp_sample_source.h"
#include "common/rimgui.h"
#include "common/widgets/double_list.h"
#include "logger.h"

#include "RTLSDRShared.h"
#include "rtlsdr_dext_bridge.h"

#include <atomic>
#include <thread>
#include <vector>

class RtlSdrDextSource : public dsp::DSPSampleSource
{
protected:
    bool is_open = false;
    bool is_started = false;

    // IOKit user-client connection + mapped IQ ring.
    uint32_t          dext_connection = 0;
    RTLSDRRingBuffer *iq_ring = nullptr;
    uint64_t          iq_ring_mapped_size = 0;

    widgets::DoubleList     samplerate_widget;
    widgets::NotatedNum<int> ppm_widget;

    int   gain = 0;                  // gain in tenths of dB, sent to the dext
    float display_gain = 0.0f;       // user-facing gain in dB
    bool  lna_agc_enabled = false;
    bool  bias_enabled = false;
    bool  changed_agc = true;
    int   last_ppm = 0;

    // Reader thread state.
    std::thread work_thread;
    std::atomic<bool> thread_should_run{false};

    // Apply current UI/state values to the dext (no-op if not streaming).
    void apply_gains();
    void apply_bias();
    void apply_ppm();

    // Reader thread body: pulls IQ from the shared ring, converts the
    // 8-bit unsigned IQ pairs into complex_t and feeds output_stream.
    void readerLoop();

public:
    RtlSdrDextSource(dsp::SourceDescriptor source)
        : DSPSampleSource(source),
          samplerate_widget("Samplerate"),
          ppm_widget("Correction##ppm", 0, "ppm")
    {
    }

    ~RtlSdrDextSource()
    {
        stop();
        close();
    }

    void set_settings(nlohmann::json settings) override;
    nlohmann::json get_settings() override;

    void open() override;
    void start() override;
    void stop() override;
    void close() override;

    void set_frequency(uint64_t frequency) override;

    void drawControlUI() override;

    void set_samplerate(uint64_t samplerate) override;
    uint64_t get_samplerate() override;

    static std::string getID() { return "rtlsdr_dext"; }
    static std::shared_ptr<dsp::DSPSampleSource> getInstance(dsp::SourceDescriptor source)
    {
        return std::make_shared<RtlSdrDextSource>(source);
    }
    static std::vector<dsp::SourceDescriptor> getAvailableSources();
};
