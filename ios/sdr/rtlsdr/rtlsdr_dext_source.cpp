//
//  rtlsdr_dext_source.cpp
//
//  See rtlsdr_dext_source.h. The byte layout of the IQ ring buffer comes
//  from RTLSDRShared.h (must stay in sync with the dext).
//

#include "rtlsdr_dext_source.h"

#include "core/exception.h"
#include "common/dsp/buffer.h"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <vector>

// ----------------------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------------------

namespace
{
    // Convenience around the C bridge: just log a warning on a non-zero
    // kern_return_t but keep going.
    void dext_call(uint32_t connection, uint32_t selector, uint64_t arg,
                   const char *label, uint64_t *out = nullptr)
    {
        int kr = satdump_rtlsdr_dext_call(connection, selector, arg, out);
        if (kr != 0)
            logger->warn("RTL-SDR Dext: %s failed (kr=0x%x)", label, kr);
    }
}

// ----------------------------------------------------------------------------
// State accessors / persistence
// ----------------------------------------------------------------------------

void RtlSdrDextSource::set_settings(nlohmann::json settings)
{
    d_settings = settings;

    display_gain    = getValueOrDefault(d_settings["gain"], display_gain);
    lna_agc_enabled = getValueOrDefault(d_settings["agc"], lna_agc_enabled);
    bias_enabled    = getValueOrDefault(d_settings["bias"], bias_enabled);
    ppm_widget.set(getValueOrDefault(d_settings["ppm_correction"], ppm_widget.get()));
    changed_agc = true;

    if (is_started)
    {
        apply_bias();
        apply_gains();
        apply_ppm();
    }
}

nlohmann::json RtlSdrDextSource::get_settings()
{
    d_settings["gain"]           = display_gain;
    d_settings["agc"]            = lna_agc_enabled;
    d_settings["bias"]           = bias_enabled;
    d_settings["ppm_correction"] = ppm_widget.get();
    return d_settings;
}

// ----------------------------------------------------------------------------
// Lifecycle
// ----------------------------------------------------------------------------

void RtlSdrDextSource::open()
{
    is_open = true;

    // Standard RTL-SDR sample rates; the dext's SetSampleRate selector
    // accepts the same set as librtlsdr.
    std::vector<double> available_samplerates = {
        250000, 1024000, 1536000, 1792000, 1920000,
        2048000, 2160000, 2400000, 2560000, 2880000, 3200000
    };
    samplerate_widget.set_list(available_samplerates, true);
}

void RtlSdrDextSource::start()
{
    DSPSampleSource::start();

    // Open the IOKit user client on the dext. Exclusive: fails if RTL-SDR
    // Host (or another app) is already connected.
    dext_connection = satdump_rtlsdr_dext_open();
    if (dext_connection == 0)
        throw satdump_exception(
            "Could not open RTL-SDR DriverKit extension. "
            "Make sure RTL-SDR Host is installed and not currently streaming.");

    // Map the shared IQ ring buffer into our address space.
    iq_ring_mapped_size = 0;
    iq_ring = (RTLSDRRingBuffer *)satdump_rtlsdr_dext_map_memory(
        dext_connection, kRTLSDRMemoryTypeIQRing, &iq_ring_mapped_size);
    if (iq_ring == nullptr)
    {
        satdump_rtlsdr_dext_close(dext_connection);
        dext_connection = 0;
        throw satdump_exception("Could not map the RTL-SDR IQ ring buffer.");
    }

    // Apply samplerate, frequency, gains, bias-tee, ppm.
    uint64_t current_samplerate = samplerate_widget.get_value();
    logger->debug("Set RTL-SDR (Dext) samplerate to %lld", (long long)current_samplerate);
    dext_call(dext_connection, kRTLSDRMethodSetSampleRate, current_samplerate, "SetSampleRate");

    is_started = true;
    changed_agc = true;

    set_frequency(d_frequency);
    apply_bias();
    apply_gains();
    apply_ppm();

    dext_call(dext_connection, kRTLSDRMethodResetBuffer, 0, "ResetBuffer");

    // Start streaming and the reader thread.
    dext_call(dext_connection, kRTLSDRMethodStartStream, 0, "StartStream");

    display_gain = (float)gain / 10.0f;

    thread_should_run = true;
    work_thread = std::thread(&RtlSdrDextSource::readerLoop, this);
}

void RtlSdrDextSource::stop()
{
    if (is_started)
    {
        // Disable bias-tee while the device is still fully active. Some dext
        // implementations reject control transfers after StopStream has torn
        // down the USB streaming state.
        if (dext_connection != 0 && bias_enabled)
            dext_call(dext_connection, kRTLSDRMethodSetBiasTee, 0, "SetBiasTee(off)");

        // Tell the dext to stop producing, then drain the reader.
        if (dext_connection != 0)
            dext_call(dext_connection, kRTLSDRMethodStopStream, 0, "StopStream");

        thread_should_run = false;
        if (output_stream)
            output_stream->stopWriter();
        if (work_thread.joinable())
            work_thread.join();

        if (dext_connection != 0)
        {
            if (iq_ring != nullptr)
                satdump_rtlsdr_dext_unmap_memory(dext_connection,
                                                 kRTLSDRMemoryTypeIQRing, iq_ring);
            iq_ring = nullptr;
            iq_ring_mapped_size = 0;

            satdump_rtlsdr_dext_close(dext_connection);
            dext_connection = 0;
        }
    }
    is_started = false;
}

void RtlSdrDextSource::close()
{
    is_open = false;
}

// ----------------------------------------------------------------------------
// Per-setting senders
// ----------------------------------------------------------------------------

void RtlSdrDextSource::set_frequency(uint64_t frequency)
{
    if (is_started && dext_connection != 0)
    {
        dext_call(dext_connection, kRTLSDRMethodSetCenterFreq, frequency, "SetCenterFreq");
        logger->debug("Set RTL-SDR (Dext) frequency to %lld", (long long)frequency);
    }
    DSPSampleSource::set_frequency(frequency);
}

void RtlSdrDextSource::apply_gains()
{
    if (!is_started || dext_connection == 0)
        return;

    if (changed_agc)
    {
        dext_call(dext_connection, kRTLSDRMethodSetAgcMode,
                  lna_agc_enabled ? 1 : 0, "SetAgcMode");
        dext_call(dext_connection, kRTLSDRMethodSetTunerGainMode,
                  lna_agc_enabled ? 0 : 1, "SetTunerGainMode");
        changed_agc = false;
    }

    if (!lna_agc_enabled)
    {
        gain = (int)(display_gain * 10.0f);
        dext_call(dext_connection, kRTLSDRMethodSetTunerGain,
                  (uint64_t)gain, "SetTunerGain");
    }
}

void RtlSdrDextSource::apply_bias()
{
    if (!is_started || dext_connection == 0)
        return;
    dext_call(dext_connection, kRTLSDRMethodSetBiasTee,
              bias_enabled ? 1 : 0, "SetBiasTee");
}

void RtlSdrDextSource::apply_ppm()
{
    if (!is_started || dext_connection == 0)
        return;
    int ppm = ppm_widget.get();
    if (ppm == last_ppm)
        return;
    // Selector reinterprets the scalar as int32.
    uint64_t arg = (uint64_t)(uint32_t)ppm;
    dext_call(dext_connection, kRTLSDRMethodSetFreqCorrection, arg, "SetFreqCorrection");
    last_ppm = ppm;
}

// ----------------------------------------------------------------------------
// UI
// ----------------------------------------------------------------------------

void RtlSdrDextSource::drawControlUI()
{
    if (is_started)
        RImGui::beginDisabled();
    samplerate_widget.render();
    if (is_started)
        RImGui::endDisabled();

    if (ppm_widget.draw())
        apply_ppm();

    if (RImGui::SteppedSliderFloat("LNA Gain", &display_gain, 0.0f, 50.0f, 0.1f, "%.1f"))
        apply_gains();
    if (is_started && RImGui::IsItemDeactivatedAfterEdit())
        display_gain = (float)gain / 10.0f;

    if (RImGui::Checkbox("AGC", &lna_agc_enabled))
    {
        changed_agc = true;
        apply_gains();
    }

    if (RImGui::Checkbox("Bias-Tee", &bias_enabled))
        apply_bias();
}

// ----------------------------------------------------------------------------
// Samplerate
// ----------------------------------------------------------------------------

void RtlSdrDextSource::set_samplerate(uint64_t samplerate)
{
    if (!samplerate_widget.set_value(samplerate, 3.2e6))
        throw satdump_exception("Unsupported samplerate : " + std::to_string(samplerate) + "!");
}

uint64_t RtlSdrDextSource::get_samplerate()
{
    return samplerate_widget.get_value();
}

// ----------------------------------------------------------------------------
// Source enumeration
// ----------------------------------------------------------------------------

std::vector<dsp::SourceDescriptor> RtlSdrDextSource::getAvailableSources()
{
    std::vector<dsp::SourceDescriptor> sources;
    if (satdump_rtlsdr_dext_is_available())
    {
        // Single entry for now: multiple-RTL-SDR-on-the-iPad needs an extra
        // round trip to the dext for per-instance identification.
        sources.push_back({getID(), "RTL-SDR (DriverKit)", "0"});
    }
    return sources;
}

// ----------------------------------------------------------------------------
// Reader thread
// ----------------------------------------------------------------------------

void RtlSdrDextSource::readerLoop()
{
    // Bytes per swap. Matches the convention used by the desktop rtlsdr
    // plugin (calculate_buffer_size_from_samplerate returns "bytes" sized
    // to fit STREAM_BUFFER_SIZE complex_t in writeBuf).
    int chunk_bytes =
        calculate_buffer_size_from_samplerate((int)samplerate_widget.get_value());
    if (chunk_bytes < 2)
        chunk_bytes = 2;
    // Round to multiple of 2 (one IQ pair).
    chunk_bytes &= ~1;

    const uint64_t data_size = iq_ring ? iq_ring->dataSize : 0;
    if (data_size == 0)
        return;

    logger->trace("RTL-SDR Dext chunk bytes: %d", chunk_bytes);

    while (thread_should_run.load(std::memory_order_relaxed))
    {
        uint64_t avail = iq_ring->writeCount - iq_ring->readCount;
        if (avail < (uint64_t)chunk_bytes)
        {
            std::this_thread::sleep_for(std::chrono::microseconds(500));
            continue;
        }

        // Two-part read across the ring's wrap point.
        const uint64_t offset = iq_ring->readCount % data_size;
        const uint64_t first  = std::min((uint64_t)chunk_bytes, data_size - offset);
        const uint64_t second = (uint64_t)chunk_bytes - first;

        const uint8_t *p0 = iq_ring->data + offset;
        const uint8_t *p1 = iq_ring->data;

        // Convert 8-bit unsigned IQ pairs straight into the output stream's
        // writeBuf (same formula as the desktop rtlsdr plugin).
        const int samples_first  = (int)(first / 2);
        const int samples_second = (int)(second / 2);

        for (int i = 0; i < samples_first; i++)
        {
            output_stream->writeBuf[i].real = (p0[i * 2 + 0] - 127.4f) / 128.0f;
            output_stream->writeBuf[i].imag = (p0[i * 2 + 1] - 127.4f) / 128.0f;
        }
        for (int i = 0; i < samples_second; i++)
        {
            output_stream->writeBuf[samples_first + i].real = (p1[i * 2 + 0] - 127.4f) / 128.0f;
            output_stream->writeBuf[samples_first + i].imag = (p1[i * 2 + 1] - 127.4f) / 128.0f;
        }

        // Publish consumption to the producer, then hand the samples
        // downstream.
        iq_ring->readCount += (uint64_t)chunk_bytes;
        output_stream->swap(samples_first + samples_second);
    }
}
