#include <extern/pybind11/include/pybind11/pybind11.h>
#include <core/logger.h>
#include "bindings.h"

namespace py = pybind11;

Logger logger;

PYBIND11_MODULE(_udevicex, m)
{
    exportUdevicex(m);
    
    auto ic = m.def_submodule("InitialConditions");
    exportInitialConditions(ic);

    auto pv = m.def_submodule("ParticleVectors");
    exportParticleVectors(pv);

    auto interactions = m.def_submodule("Interactions");
    exportInteractions(interactions);
    
    auto integrators = m.def_submodule("Integrators");
    exportIntegrators(integrators);
}
