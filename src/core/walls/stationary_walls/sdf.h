#pragma once

#include <core/field/from_file.h>
#include <memory>

class StationaryWall_SDF
{
public:
    StationaryWall_SDF(const YmrState *state, std::string sdfFileName, float3 sdfH);
    StationaryWall_SDF(StationaryWall_SDF&&);

    void setup(MPI_Comm& comm, DomainInfo domain);

    const FieldDeviceHandler& handler() const;

private:
    std::unique_ptr<FieldFromFile> impl;
};
