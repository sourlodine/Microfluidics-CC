/*
 *  main.cpp
 *  Part of CTC/device-gen/ctc-ichip/
 *
 *  Created and authored by Kirill Lykov on 2015-09-7.
 *  Copyright 2015. All rights reserved.
 *
 *  Users are NOT authorized
 *  to employ the present software for their own publications
 *  before getting a written permission from the author of this file.
 */

#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <iostream>
#include <vector>
#include <algorithm>
#include <stdexcept>
#include <argument-parser.h>
#include "../common/device-builder.h"
#include "../common/common.h"
#include "../common/collage.h"
#include "../common/redistance.h"
#include "../common/2Dto3D.h"

using namespace std;

struct Egg 
{
    float r1, r2, alpha;

    Egg() 
    : r1(12.0f), r2(8.5f), alpha(0.03f) 
    {
    }    

    float x2y(float x) const {
        return sqrt(r2*r2 * exp(-alpha * x) * (1.0f - x*x/r1/r1));
    }
    
    void run(vector<float>& vx, vector<float>& vy) {
        int N = 500;
        float dx = 2.0f * r1 / (N - 1);
        for (int i = 0; i < N; ++i) {
            float x = i * dx - r1;
            float y = x2y(x);
            vx.push_back(x);
            vy.push_back(y);
        }
        
        auto vxRev = vx;
        vx.insert(vx.end(), vxRev.rbegin(), vxRev.rend());

        auto vyRev = vy;
        for_each(vyRev.begin(), vyRev.end(), [](float& i) { i *= -1.0f; });
        vy.insert(vy.end(), vyRev.rbegin(), vyRev.rend());
    }
};

class CTCiChip1Builder : public DeviceBuilder
{
    int m_nrepeat;
    const float m_angle;
    float m_desiredSubdomainSzX;
public:
    CTCiChip1Builder()
    : DeviceBuilder(56.0f, 32.0f, 128.0f),
      m_nrepeat(0), m_angle(1.7f * M_PI / 180.0f)
    {}

    CTCiChip1Builder& setNColumns(int ncolumns) 
    {
        m_ncolumns = ncolumns;
        return *this;
    }

    CTCiChip1Builder& setNRows(int nrows) 
    {
        m_nrows = nrows;
        return *this;
    }

    CTCiChip1Builder& setRepeat(float nrepeat)
    {
        m_nrepeat = nrepeat;
        return *this;
    }

    CTCiChip1Builder& setResolution(float resolution)          
    {
        m_resolution = resolution;
        return *this;
    }

    CTCiChip1Builder& setZWallWidth(float zmargin) 
    {
        m_zmargin = zmargin;
        return *this;
    }

    CTCiChip1Builder& setDiseredSubdomainX(float x)
    {
        m_desiredSubdomainSzX = x;
        return *this;
    }

    CTCiChip1Builder& setFileNameFor2D(const std::string& outFileName2D)
    {
        m_outFileName2D = outFileName2D;
        return *this;
    }

    CTCiChip1Builder& setFileNameFor3D(const std::string& outFileName3D)
    {
        m_outFileName3D = outFileName3D;
        return *this;
    }
    
    void build();
        
private:
    void generateUnitSDF(vector<float>& sdf) const;

    void shiftRows(int rowNX, int rowNY, float rowSizeX, float rowSizeY, const SDF& rowObstacles,
                   float& padding, float& addPadding, int& shiftedRowNX, float& shiftedRowSizeX,std::vector<SDF>& shiftedRows) const;
};

void CTCiChip1Builder::build() 
{
    if (m_ncolumns *  m_nrows *  m_nrepeat * m_resolution * m_zmargin == 0.0f || m_outFileName3D.length() == 0)
        throw std::runtime_error("Invalid parameters");
    
    // 1 Create 1 obstacle
    m_unitNX = static_cast<int>(m_unitSizeX * m_resolution);
    m_unitNY = static_cast<int>(m_unitSizeY * m_resolution);
    m_unitNZ = static_cast<int>(m_unitSizeZ * m_resolution);

    SDF eggSdf;
    generateUnitSDF(eggSdf);

    // 2 Create 1 row of obstacles
    int rowNX = m_ncolumns*m_unitNX;
    int rowNY = m_unitNY;
    int rowSizeX = m_ncolumns * m_unitSizeX;
    int rowSizeY = m_unitSizeY;
    SDF rowObstacles;
    populateSDF(m_unitNX, m_unitNY, m_unitSizeX, m_unitSizeY, eggSdf, m_ncolumns, 1, rowObstacles);

    // 3 Shift rows
    float padding = 0.0f;
    float addPadding = 0.0f;
    int shiftedRowNX = 0; // they are all the same length
    float shiftedRowSizeX = 0.0f;

    std::vector<SDF> shiftedRows;
    shiftRows(rowNX, rowNY, rowSizeX, rowSizeY, rowObstacles, padding, addPadding, shiftedRowNX, shiftedRowSizeX, shiftedRows);

    // 4 Collage rows
    SDF finalSDF;
    collageSDFWithWall(shiftedRowNX, rowNY, shiftedRowSizeX, rowSizeY, shiftedRows, m_nrows, addPadding, finalSDF);

    // 5 Apply redistancing for the result
    float finalExtent[] = {shiftedRowSizeX, static_cast<float>(m_nrows * rowSizeY)};
    int finalN[] = {shiftedRowNX, m_nrows*rowNY};
    const float dx = finalExtent[0] / (finalN[0] - 1);
    const float dy = finalExtent[1] / (finalN[1] - 1);
    Redistance redistancer(0.25f * min(dx, dy), dx, dy, finalN[0], finalN[1]);
    redistancer.run(m_niterRedistance, &finalSDF[0]);

    // 6 Repeat this pattern
    SDF finalSDF2;
    populateSDF(finalN[0], finalN[1], finalExtent[0], finalExtent[1], finalSDF, 1, m_nrepeat, finalSDF2);
    std::swap(finalSDF, finalSDF2);

    // 6 Write result to the file
    if (m_outFileName2D.length() != 0)
        writeDAT(m_outFileName2D, finalSDF, finalN[0], m_nrepeat * finalN[1], 1, finalExtent[0], m_nrepeat * finalExtent[1], 1.0f);

    conver2Dto3D(finalN[0], m_nrepeat * finalN[1], finalExtent[0], m_nrepeat*finalExtent[1], finalSDF,
                 m_unitNZ, m_unitSizeZ - 2.0f*m_zmargin, m_zmargin, m_outFileName3D);
}

void CTCiChip1Builder::generateUnitSDF(vector<float>& sdf) const
{
    vector<float> xs, ys;
    Egg egg;
    egg.run(xs, ys);

    const float xlb = -m_unitSizeX/2.0f;
    const float ylb = -m_unitSizeY/2.0f;

    sdf.resize(m_unitNX * m_unitNY, 0.0f);
    const float dx = m_unitSizeX / (m_unitNX - 1);
    const float dy = m_unitSizeY / (m_unitNY - 1);
    const int nsamples = xs.size();

    for(int iy = 0; iy < m_unitNY; ++iy)
    for(int ix = 0; ix < m_unitNX; ++ix)
    {
        const float x = xlb + ix * dx;
        const float y = ylb + iy * dy;

        float distance2 = 1e6;
        int iclosest = 0;
        for(int i = 0; i < nsamples ; ++i)
        {
            const float xd = xs[i] - x;
            const float yd = ys[i] - y;
            const float candidate = xd * xd + yd * yd;

            if (candidate < distance2)
            {
                iclosest = i;
                distance2 = candidate;
            }
        }

        float s = -1;

        {
            const float ycurve = egg.x2y(x);
            if (x >= -egg.r1 && x <= egg.r1 && fabs(y) <= ycurve)
                s = +1;
        }


        sdf[ix + m_unitNX * iy] = s * sqrt(distance2);
    }
}

void CTCiChip1Builder::shiftRows(int rowNX, int rowNY, float rowSizeX, float rowSizeY, const SDF& rowObstacles,
                                 float& padding, float& addPadding, int& shiftedRowNX, float& shiftedRowSizeX,std::vector<SDF>& shiftedRows) const
{
    const int nRowsPerShift = static_cast<int>(ceil(m_unitSizeX / (m_unitSizeY * tan(m_angle))));
    if (fabs(m_unitSizeX / (m_unitSizeY * tan(m_angle)) - nRowsPerShift) > 1e-1) {
        throw std::runtime_error("Suggest changing the angle");
    }

    padding = float(ceil(m_nrows * m_unitSizeY * tan(m_angle)));
    // TODO Do I need this nUniqueRows?
    int nUniqueRows = m_nrows;
    if (m_nrows > nRowsPerShift) {
        nUniqueRows = nRowsPerShift;
        padding = float(round(nRowsPerShift * m_unitSizeY * tan(m_angle)));
    }

    // TODO fix this stupid workaround
    if (padding < 32.0f)
        padding = 0.0f;
    if (padding == 57.0f)
        padding = m_unitSizeX;
    
    // additional hack to have domain size in X direction to be devisible by desiredSubdomainSzX
    {
        float origSzX = m_ncolumns*m_unitSizeX + padding;
        addPadding = (int(origSzX/m_desiredSubdomainSzX) + 1)*m_desiredSubdomainSzX - origSzX;
        padding = padding + addPadding; // adjust padding to have desired size
    }

    std::cout << "Launching rows generation. New size = "<< m_ncolumns*m_unitSizeX + padding << std::endl;
    shiftedRows.resize(nUniqueRows);
    for (int i = 0; i < nUniqueRows; ++i) {
        float xshift = (nUniqueRows - i - 1) * 32.0f * tan(m_angle);
        shiftSDF(rowNX, rowNY, rowSizeX, rowSizeY, rowObstacles, xshift, padding, shiftedRowNX, shiftedRowSizeX, shiftedRows[i]);
    }
}


int main(int argc, char ** argv)
{
    ArgumentParser argp(vector<string>(argv, argv + argc));

    int nColumns = argp("-nColumns").asInt(1);
    int nRows = argp("-nRows").asInt(1);
    int nRepeat = argp("-nRepeat").asInt(1);    
    float zMargin = static_cast<float>(argp("-zMargin").asDouble(5.0));
    float resolution = static_cast<float>(argp("-zResolution").asDouble(1.0));
    std::string outFileName = argp("-out").asString("3d");

    CTCiChip1Builder builder;
    try {
        builder.setNColumns(nColumns)
               .setNRows(nRows)
               .setRepeat(nRepeat)
               .setResolution(resolution)
               .setZWallWidth(zMargin)
               .setFileNameFor2D("2d")
               .setFileNameFor3D(outFileName)
               .setDiseredSubdomainX(64.0f)
               .build();
    } catch(const std::exception& ex) {
        std::cout << "ERROR: " << ex.what() << std::endl;
    }
    return 0;
}

