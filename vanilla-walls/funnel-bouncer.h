#include <vector>
#include <tuple>

using namespace std;

// TODO compute index and than sort atoms in frozen layer according to it
// for now use this index for filtering only
class AngleIndex
{
    std::vector<int> index;
    float sectorSz;
    size_t nSectors;

    // give angle between [0, 2PI]
    float getAngle(const float x, const float y) const
    {
        return atan2(y, x) + M_PI;
    }

public:

    AngleIndex(float rc, float y0)
    : sectorSz(0.0f), nSectors(0.0f)
    {
        assert(y0 < 0);
        sectorSz = 2.0f * asin(rc/sqrt(-y0));
        nSectors = static_cast<size_t>(2.0f * M_PI) / sectorSz + 1;
    }

    void run(const std::vector<float>& xp, const std::vector<float>& yp)
    {
        index.resize(xp.size());
        for (size_t i = 0; i < index.size(); ++i)
            index[i] = computeIndex(xp[i], yp[i]);
    }

    bool isClose(int srcAngInd, size_t frParticleInd) const
    {
        int destAngInd = getIndex(frParticleInd);
        return destAngInd == srcAngInd
                || (destAngInd + 1)%nSectors == srcAngInd
                || (destAngInd + nSectors - 1)%nSectors == srcAngInd;
    }

    int computeIndex(const float x, const float y) const
    {
        float angle = getAngle(x, y);
        assert(angle >= 0.0f && angle <= 2.0f * M_PI);
        return trunc(angle/sectorSz);
    }

    int getIndex(size_t i) const { return index[i]; }
};

struct TomatoSandwich: SandwichBouncer
{
    float xc = 0, yc = 0, zc = 0;
    float radius2 = 1;

    const float rc = 1.0;

    RowFunnelObstacle funnelLS;
    Particles frozenLayer[3]; // three layers every one is rc width
    AngleIndex angleIndex[3];

    TomatoSandwich(const float boxLength)
    : SandwichBouncer(boxLength), funnelLS(7.0f, 10.0f, 10.0f, 64, 64),
      frozenLayer{Particles(0, boxLength), Particles(0, boxLength), Particles(0, boxLength)},
      angleIndex{AngleIndex(rc, funnelLS.getY0()), AngleIndex(rc, funnelLS.getY0()), AngleIndex(rc, funnelLS.getY0())}
    {}

    Particles carve(const Particles& particles)
    {
        Particles remaining0 = carveAllLayers(particles);
        return SandwichBouncer::carve(remaining0);
    }

    void _mark(bool * const freeze, Particles p)
	{
	    SandwichBouncer::_mark(freeze, p);

	    for(int i = 0; i < p.n; ++i)
	    {
		const float x = p.xp[i] - xc;
		const float y = p.yp[i] - yc;
#if 1
		freeze[i] |= funnelLS.isInside(x, y);
#else
		const float r2 = x * x + y * y;

		freeze[i] |= r2 < radius2;
#endif
	    }
	}
 
    float _compute_collision_time(const float _x0, const float _y0,
			  const float u, const float v, 
			  const float xc, const float yc, const float r2)
	{
	    const float x0 = _x0 - xc;
	    const float y0 = _y0 - yc;
	    	    
	    const float c = x0 * x0 + y0 * y0 - r2;
	    const float b = 2 * (x0 * u + y0 * v);
	    const float a = u * u + v * v;
	    const float d = sqrt(b * b - 4 * a * c);

	    return (-b - d) / (2 * a);
	}

    bool _handle_collision(float& x, float& y, float& z,
			   float& u, float& v, float& w,
			   float& dt)
	{
#if 1
	    if (!funnelLS.isInside(x, y))
		return false;

	    const float xold = x - dt * u;
	    const float yold = y - dt * v;
	    const float zold = z - dt * w;

	    float t = 0;
	    
	    for(int i = 1; i < 30; ++i)
	    {
		const float tcandidate = t + dt / (1 << i);
		const float xcandidate = xold + tcandidate * u;
		const float ycandidate = yold + tcandidate * v;
		
		 if (!funnelLS.isInside(xcandidate, ycandidate))
		     t = tcandidate;
	    }

	    const float lambda = 2 * t - dt;
		    
	    x = xold + lambda * u;
	    y = yold + lambda * v;
	    z = zold + lambda * w;
	   
	    u  = -u;
	    v  = -v;
	    w  = -w;
	    dt = dt - t;

	    return true;
	    
#else
	    const float r2 =
		(x - xc) * (x - xc) +
		(y - yc) * (y - yc) ;
		
	    if (r2 >= radius2)
		return false;
	    
	    assert(dt > 0);
			
	    const float xold = x - dt * u;
	    const float yold = y - dt * v;
	    const float zold = z - dt * w;

	     const float r2old =
		(xold - xc) * (xold - xc) +
		 (yold - yc) * (yold - yc) ;

	     if (r2old < radius2)
		 printf("r2old : %.30f\n", r2old);
	     
	    assert(r2old >= radius2);

	    const float t = _compute_collision_time(xold, yold, u, v, xc, yc, radius2);
	    if (t < 0)
		printf("t is %.20e\n", t);
	    
	    assert(t >= 0);
	    assert(t <= dt);
		    
	    const float lambda = 2 * t - dt;
		    
	    x = xold + lambda * u;
	    y = yold + lambda * v;
	    z = zold + lambda * w;
	    
	    u  = -u;
	    v  = -v;
	    w  = -w;
	    dt = dt - t;

	    return true;
#endif
	}
    
    void bounce(Particles& dest, const float _dt)
	{
	    int gfailcc = 0, gokcc = 0;
	    
#pragma omp parallel
	    {
		int failcc = 0, okcc = 0;

#pragma omp for
		for(int i = 0; i < dest.n; ++i)
		{
		    float x = dest.xp[i];
		    float y = dest.yp[i];
		    float z = dest.zp[i];
		    float u = dest.xv[i];
		    float v = dest.yv[i];
		    float w = dest.zv[i];
		    float dt = _dt;
		    
		    bool wascolliding = false, collision;
		    int passes = 0;
		    do
		    {
			collision = false;
			collision |= SandwichBouncer::_handle_collision(x, y, z, u, v, w, dt);
			collision |= _handle_collision(x, y, z, u, v, w, dt);
		    
			wascolliding |= collision;
			passes++;

			if (passes >= 100)
			    break;
		    }
		    while(collision);

		    if (passes >= 2)
			if (!collision)
			    okcc++;//
			else
			    failcc++;//
		
		    if (wascolliding)
		    {
			dest.xp[i] = x;
			dest.yp[i] = y;
			dest.zp[i] = z;
			dest.xv[i] = u;
			dest.yv[i] = v;
			dest.zv[i] = w;
		    }
		}
		//while(collision);

#pragma omp critical
		{
		    gfailcc += failcc;
		    gokcc += okcc;
		}
	    }

	    if (gokcc)
		printf("successfully solved %d complex collisions\n", gokcc);

	    if (gfailcc)
	    {
		printf("FAILED to solve %d complex collisions\n", gfailcc);
		//abort();
	    }
	}
 void compute_forces(const float kBT, const double dt, Particles& freeParticles) const
    {
        SandwichBouncer::compute_forces(kBT, dt, freeParticles);
        computePairDPD(kBT, dt, freeParticles);
    }

 void vmd_xyz(const char * path)
 {
     
     FILE * f = fopen(path, "w");

     if (f == NULL)
     {
	 printf("I could not open the file <%s>\n", path);
	 printf("Aborting now.\n");
	 abort();
     }

     tuple< vector<float>, vector<float>, vector<float>> all;

     auto _add = [&](const float x, const float y, const float z)
	 {
	     get<0>(all).push_back(x);
	     get<1>(all).push_back(y);
	     get<2>(all).push_back(z);
	 };

     float x0 = -20;
    
     float extent = 3;
     float xextent = 10;
     while(x0 <= 20)
     {
	 float z0 = -20 + 1.5;
	 printf("x0 is %f\n", x0);
	 while(z0 <= 20)
	 {
	 
	     for(int j = 0; j < 3; ++j)
		 for(int i = 0; i < frozenLayer[j].n; ++i)
		 {
		     const float x = frozenLayer[j].xp[i] + x0;

		       if (x >= -20 && x < 20)
			 _add(x, frozenLayer[j].yp[i], frozenLayer[j].zp[i] + z0);
		 }

	     z0 += extent;
	 }
	 x0 += xextent;
     }
     
     fprintf(f, "%d\n", get<0>(all).size());
     fprintf(f, "mymolecule\n");
    
     for(int i = 0; i < get<0>(all).size(); ++i)
	 fprintf(f, "1 %f %f %f\n", get<0>(all)[i], get<1>(all)[i], get<2>(all)[i]);
    
     fclose(f);

     printf("vmd_xyz: wrote to <%s>\n", path);
	    
     printf("exit now...\n");
     exit(0);
 }

private:
    //dpd forces computations related methods
    Particles carveLayer(const Particles& input, size_t indLayer, float bottom, float top);
    Particles carveAllLayers(const Particles& p);
    void computeDPDPairForLayer(const float kBT, const double dt, int i, const float* coord,
                const float* vel, float* df, const float offsetX, int seed1) const;
    void computePairDPD(const float kBT, const double dt, Particles& freeParticles) const;
    void _dpd_forces_1particle(size_t layerIndex, const float kBT, const double dt,
            int i, const float* offset, const float* coord, const float* vel, float* df,
            const int giddstart) const;
};

Particles TomatoSandwich::carveLayer(const Particles& input, size_t indLayer, float bottom, float top)
{
    std::vector<bool> maskSkip(input.n, false);
    for (int i = 0; i < input.n; ++i)
    {
        int bbIndex = funnelLS.getBoundingBoxIndex(input.xp[i], input.yp[i]);
        if (bbIndex == 0 && input.zp[i] > bottom && input.zp[i] < top)
            maskSkip[i] = true;
    }
    Particles splitToSkip[2] = {Particles(0, input.L), Particles(0, input.L)};
    Bouncer::splitParticles(input, maskSkip, splitToSkip);

    frozenLayer[indLayer] = splitToSkip[0];
    angleIndex[indLayer].run(frozenLayer[indLayer].xp, frozenLayer[indLayer].yp);

    for(int i = 0; i < frozenLayer[indLayer].n; ++i)
        frozenLayer[indLayer].xv[i] = frozenLayer[indLayer].yv[i] = frozenLayer[indLayer].zv[i] = 0.0f;

    return splitToSkip[1];
}

Particles TomatoSandwich::carveAllLayers(const Particles& p)
{
    // in carving we get all particles inside the obstacle so they are not in consideration any more
    // But we don't need all these particles for this code, we cleaned them all except layer between [-rc/2, rc/2]
    std::vector<bool> maskFrozen(p.n);
    for (int i = 0; i < p.n; ++i)
    {
        // make holes in frozen planes for now
        maskFrozen[i] = funnelLS.isInside(p.xp[i], p.yp[i]);
    }

    Particles splittedParticles[2] = {Particles(0, p.L), Particles(0, p.L)};
    Bouncer::splitParticles(p, maskFrozen, splittedParticles);

    Particles pp = carveLayer(splittedParticles[0], 0, -3.0f * rc/2.0, -rc/2.0);
    Particles ppp = carveLayer(pp, 1, -rc/2.0, rc/2.0);
    carveLayer(ppp, 2, rc/2.0, 3.0 * rc/2.0);

    return splittedParticles[1];
}

void TomatoSandwich::computeDPDPairForLayer(const float kBT, const double dt, int i, const float* coord,
        const float* vel, float* df, const float offsetX, int seed1) const
    {
    float w = 3.0f * rc; // width of the frozen layers

    float zh = coord[2] > 0.0f ? 0.5f : -0.5f;
    float zOffset = -trunc(coord[2] / w + zh) * w;
    // shift atom to the range [-w/2, w/2]
    float coordShifted[] = {coord[0], coord[1], coord[2] + zOffset};
    assert(coordShifted[2] >= -w/2.0f && coordShifted[2] <= w/2.0f);

    int coreLayerIndex = trunc((coordShifted[2] + w/2)/rc);
    if (coreLayerIndex == 3) // iff coordShifted[2] == 1.5, temporary workaround
        coreLayerIndex = 2;

    assert(coreLayerIndex >= 0 && coreLayerIndex < 3);

    float layersOffsetZ[] = {0.0f, 0.0f, 0.0f};
    if (coreLayerIndex == 0)
        layersOffsetZ[2] = -w;
    else if (coreLayerIndex == 2)
        layersOffsetZ[0] = w;

    for (int lInd = 0; lInd < 3; ++lInd) {
        float layerOffset[] = {offsetX, 0.0f, layersOffsetZ[lInd]};
        _dpd_forces_1particle(lInd, kBT, dt, i, layerOffset, coordShifted, vel, df, seed1);
    }
}

void TomatoSandwich::computePairDPD(const float kBT, const double dt, Particles& freeParticles) const
{
    int seed1 = freeParticles.myidstart;
    float xskin, yskin;
    funnelLS.getSkinWidth(xskin, yskin);

    for (int i = 0; i < freeParticles.n; ++i) {

        if (funnelLS.insideBoundingBox(freeParticles.xp[i], freeParticles.yp[i])) {

            // not sure it gives performance improvements since bounding box usually is small enough
            //if (!funnelLS.isBetweenLayers(freeParticles.xp[i], freeParticles.yp[i], 0.0f, rc + 1e-2))
            //    continue;

            //shifted position so coord.z == origin(layer).z which is 0
            float coord[] = {freeParticles.xp[i], freeParticles.yp[i], freeParticles.zp[i]};
            float vel[] = {freeParticles.xv[i], freeParticles.yv[i], freeParticles.zv[i]};
            float df[] = {0.0, 0.0, 0.0};

            // shift atom to the central box in the row
            float offsetCoordX = funnelLS.getOffset(coord[0]);
            coord[0] += offsetCoordX;

            computeDPDPairForLayer(kBT, dt, i, coord, vel, df, 0.0f, seed1);

            float frozenOffset = funnelLS.getCoreDomainLength(0);

            if ((fabs(coord[0]  - funnelLS.getCoreDomainLength(0)/2.0f) + xskin) < rc)
            {
                float signOfX = 1.0f - 2.0f * signbit(coord[0]);
                computeDPDPairForLayer(kBT, dt, i, coord, vel, df, signOfX*frozenOffset, seed1);
            }

            freeParticles.xa[i] += df[0];
            freeParticles.ya[i] += df[1];
            freeParticles.za[i] += df[2];
        }
    }
    ++frozenLayer[0].saru_tag;
    ++frozenLayer[1].saru_tag;
    ++frozenLayer[2].saru_tag;
}

void TomatoSandwich::_dpd_forces_1particle(size_t layerIndex, const float kBT, const double dt,
        int i, const float* offset,
        const float* coord, const float* vel, float* df, // float3 arrays
        const int giddstart) const
{
    const Particles& frLayer = frozenLayer[layerIndex];

    const float xdomainsize = frLayer.L;
    const float ydomainsize = frLayer.L;
    const float zdomainsize = frLayer.L;

    const float xinvdomainsize = 1.0f / xdomainsize;
    const float yinvdomainsize = 1.0f / xdomainsize;
    const float zinvdomainsize = 1.0f / zdomainsize;

    const float invrc = 1.0f;
    const float gamma = 45.0f;
    const float sigma = sqrt(2.0f * gamma * kBT);
    const float sigmaf = sigma / sqrt(dt);
    const float aij = 2.5f;

    float xf = 0, yf = 0, zf = 0;

    const int dpid = giddstart + i;


    int srcAngIndex = angleIndex[layerIndex].computeIndex(coord[0], coord[1]);
    for(int j = 0; j < frLayer.n; ++j)
    {
        if (!angleIndex[layerIndex].isClose(srcAngIndex, j)) {
            continue;
        }

        const int spid = frLayer.myidstart + j;

        if (spid == dpid)
        continue;

        const float xdiff = coord[0] - (frLayer.xp[j] + offset[0]);
        const float ydiff = coord[1] - (frLayer.yp[j] + offset[1]);
        const float zdiff = coord[2] - (frLayer.zp[j] + offset[2]);

        const float _xr = xdiff - xdomainsize * floorf(0.5f + xdiff * xinvdomainsize);
        const float _yr = ydiff - ydomainsize * floorf(0.5f + ydiff * yinvdomainsize);
        const float _zr = zdiff - zdomainsize * floorf(0.5f + zdiff * zinvdomainsize);

        const float rij2 = _xr * _xr + _yr * _yr + _zr * _zr;
        float invrij = 1./sqrtf(rij2);

        if (rij2 == 0)
            invrij = 100000;

        const float rij = rij2 * invrij;
        const float wr = max((float)0, 1 - rij * invrc);

        const float xr = _xr * invrij;
        const float yr = _yr * invrij;
        const float zr = _zr * invrij;

        assert(frLayer.xv[j] == 0 && frLayer.yv[j] == 0 && frLayer.zv[j] == 0); //TODO remove v
        const float rdotv =
        xr * (vel[0] - frLayer.xv[j]) +
        yr * (vel[1] - frLayer.yv[j]) +
        zr * (vel[2] - frLayer.zv[j]);

        const float mysaru = saru(min(spid, dpid), max(spid, dpid), frLayer.saru_tag);
        const float myrandnr = 3.464101615f * mysaru - 1.732050807f;

        const float strength = (aij - gamma * wr * rdotv + sigmaf * myrandnr) * wr;

        xf += strength * xr;
        yf += strength * yr;
        zf += strength * zr;
    }

    df[0] += xf;
    df[1] += yf;
    df[2] += zf;
}
