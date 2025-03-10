#pragma once

#include "module_demod_base.h"
#include "common/dsp/utils/random.h"
#include "common/dsp/demod/quadrature_demod.h"
#include "common/dsp/utils/agc2.h"
#include "common/dsp/clock_recovery/clock_recovery_gardner2.h"
#include "common/dsp/filter/fir.h"

namespace demod
{
    class XFSKBurstDemodModule : public BaseDemodModule
    {
    protected:
        std::shared_ptr<dsp::FIRBlock<complex_t>> lpf1;
        std::shared_ptr<dsp::QuadratureDemodBlock> qua;
        std::shared_ptr<dsp::AGC2Block<float>> agc2;
        std::shared_ptr<dsp::GardnerClockRecovery2Block> rec;

        int8_t *sym_buffer;

    public:
        XFSKBurstDemodModule(std::string input_file, std::string output_file_hint, nlohmann::json parameters);
        ~XFSKBurstDemodModule();
        void init();
        void stop();
        void process();

    public:
        static std::string getID();
        virtual std::string getIDM() { return getID(); };
        static std::vector<std::string> getParameters();
        static std::shared_ptr<ProcessingModule> getInstance(std::string input_file, std::string output_file_hint, nlohmann::json parameters);
    };
}