//
//  main.cpp
//
//  PLUGIN_LOADER glue for the iOS-only RTL-SDR DriverKit source plugin.
//  Registers RtlSdrDextSource with SatDump's DSP-source registry exactly
//  the same way the desktop rtlsdr_sdr_support plugin registers its own.
//

#include "core/plugin.h"
#include "logger.h"

#include "rtlsdr_dext_source.h"

class RtlSdrDextSupport : public satdump::Plugin
{
public:
    std::string getID()
    {
        return "rtlsdr_dext_support";
    }

    void init()
    {
        satdump::eventBus->register_handler<dsp::RegisterDSPSampleSourcesEvent>(registerSources);
    }

    static void registerSources(const dsp::RegisterDSPSampleSourcesEvent &evt)
    {
        evt.dsp_sources_registry.insert(
            {RtlSdrDextSource::getID(),
             {RtlSdrDextSource::getInstance, RtlSdrDextSource::getAvailableSources}});
    }
};

PLUGIN_LOADER(RtlSdrDextSupport)
