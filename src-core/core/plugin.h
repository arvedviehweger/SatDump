#pragma once

#include "dll_export.h"
#include <memory>
#include <map>
#include "common/event_bus.h"

// SatDump normally loads its plugins as shared libraries at runtime through
// dlopen(). Some platforms (notably iOS) do not allow loading arbitrary
// dynamic libraries, so there the plugins are linked statically into the
// application instead.
//
// SATDUMP_STATIC_PLUGINS selects that static-linking mode. It is enabled
// automatically on iOS, but can also be turned on explicitly for any other
// fully-static build.
#if defined(SATDUMP_IOS) && !defined(SATDUMP_STATIC_PLUGINS)
#define SATDUMP_STATIC_PLUGINS 1
#endif

#ifdef SATDUMP_STATIC_PLUGINS

// Static-plugin mode: each plugin registers a factory function at static
// initialization time. loadPlugins() then instantiates every registered
// plugin. The anonymous namespace gives every plugin translation unit its
// own factory/registrar symbols with internal linkage, so there are no
// symbol collisions when several plugins are linked into one binary.
#define PLUGIN_LOADER(constructor)                                            \
    namespace                                                                 \
    {                                                                         \
        satdump::Plugin *satdump_static_plugin_factory()                       \
        {                                                                     \
            return (satdump::Plugin *)new constructor();                       \
        }                                                                     \
        [[maybe_unused]] const satdump::StaticPluginRegistrar                  \
            satdump_static_plugin_registrar(&satdump_static_plugin_factory);   \
    }

#else

// Default mode: export an extern "C" "loader" symbol that dlopen()/dlsym()
// pick up from the plugin shared library.
#define PLUGIN_LOADER(constructor)                       \
    extern "C"                                           \
    {                                                    \
        satdump::Plugin *loader()                        \
        {                                                \
            return (satdump::Plugin *)new constructor(); \
        }                                                \
    }

#endif

namespace satdump
{
    struct SatDumpStartedEvent
    {
    };

    class Plugin
    {
    public:
        Plugin() {}
        virtual std::string getID() = 0;
        virtual void init() = 0;
        virtual ~Plugin(){};
    };

#ifdef SATDUMP_STATIC_PLUGINS
    // Factory function producing a new plugin instance.
    typedef Plugin *(*PluginFactory)();

    // Registers a statically-linked plugin factory. Called automatically by
    // the PLUGIN_LOADER macro during static initialization.
    SATDUMP_DLL void registerStaticPlugin(PluginFactory factory);

    // Helper whose constructor registers a plugin factory. Used by the
    // PLUGIN_LOADER macro so registration happens before main().
    struct StaticPluginRegistrar
    {
        StaticPluginRegistrar(PluginFactory factory) { registerStaticPlugin(factory); }
    };
#endif

    SATDUMP_DLL extern std::map<std::string, std::shared_ptr<satdump::Plugin>> loaded_plugins;
    SATDUMP_DLL extern std::shared_ptr<EventBus> eventBus;
}; // namespace satdump

void loadPlugins(std::map<std::string, std::shared_ptr<satdump::Plugin>> &loaded_plugins = satdump::loaded_plugins);
