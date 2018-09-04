#pragma once

#include "write_xdmf.h"

class XDMFGridDumper : public XDMFDumper
{
protected:
    int3 localResolution, globalResolution;
    float3 h;

    void writeXMFHeader   (FILE *xmf, float t) override;
    void writeXMFFooter   (FILE *xmf) override;
    void writeXMFGeometry (FILE *xmf, std::string currentFname) override;
    void writeXMFData     (FILE *xmf, std::string currentFname) override;

    void writeHeavy(std::string currentFname, std::vector<const float*> channelData);
    
public:
    XDMFGridDumper(MPI_Comm comm, int3 nranks3D, std::string fileNamePrefix, int3 localResolution, float3 h,
                   std::vector<std::string> channelNames, std::vector<ChannelType> channelTypes);

    ~XDMFGridDumper();

    void dump(std::vector<const float*> channelData, const float t);
};
