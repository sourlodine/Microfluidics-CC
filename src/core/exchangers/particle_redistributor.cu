#include "particle_redistributor.h"

#include "exchange_helpers.h"
#include "utils/common.h"
#include "utils/face_dispatch.h"
#include "utils/fragments_mapping.h"

#include <core/celllist.h>
#include <core/pvs/packers/particles.h>
#include <core/pvs/particle_vector.h>
#include <core/pvs/views/pv.h>
#include <core/utils/cuda_common.h>
#include <core/utils/kernel_launch.h>

enum class PackMode
{
    Query, Pack
};

namespace ParticleRedistributorKernels
{
inline __device__ int encodeCellId1d(int cid, int ncells)
{
    if      (cid <  0     ) return -1;
    else if (cid >= ncells) return  1;
    else                    return  0;
}

inline __device__ int3 encodeCellId(int3 cid, int3 ncells)
{
    cid.x = encodeCellId1d(cid.x, ncells.x);
    cid.y = encodeCellId1d(cid.y, ncells.y);
    cid.z = encodeCellId1d(cid.z, ncells.z);
    return cid;
}

inline __device__ bool hasToLeave(int3 dir)
{
    return dir.x != 0 || dir.y != 0 || dir.z != 0;
}

template <PackMode packMode>
__global__ void getExitingParticles(CellListInfo cinfo, PVview view, DomainInfo domain,
                                    ParticlePackerHandler packer, BufferOffsetsSizesWrap dataWrap)
{
    const int gid = blockIdx.x*blockDim.x + threadIdx.x;
    const int faceId = blockIdx.y;
    int cid;
    int dx, dy, dz;

    bool valid = distributeThreadsToFaceCell(cid, dx, dy, dz, gid, faceId, cinfo);

    if (!valid) return;

    // The following is called for every outer cell and exactly once for each
    // Now for each cell we check its every particle if it needs to move

    int pstart = cinfo.cellStarts[cid];
    int pend   = cinfo.cellStarts[cid+1];

#pragma unroll 2
    for (int i = 0; i < pend-pstart; i++)
    {
        const int srcId = pstart + i;
        Particle p;
        view.readPosition(p, srcId);

        int3 dir = cinfo.getCellIdAlongAxes<CellListsProjection::NoClamp>(p.r);

        dir = encodeCellId(dir, cinfo.ncells);

        if (p.isMarked()) continue;
        
        if (hasToLeave(dir))
        {
            const int bufId = FragmentMapping::getId(dir);

            int myId = atomicAdd(dataWrap.sizes + bufId, 1);

            if (packMode == PackMode::Query)
            {
                continue;
            }
            else
            {
                auto shift = ExchangersCommon::getShift(domain.localSize, dir);

                const int numElements = dataWrap.offsets[bufId+1] - dataWrap.offsets[bufId];

                auto buffer = dataWrap.getBuffer(bufId);

                packer.particles.packShift(srcId, myId, buffer, numElements, shift);
                
                // mark the particle as exited to assist cell-list building
                Float3_int pos = p.r2Float3_int();
                pos.mark();
                view.writePosition(srcId, pos.toFloat4());
            }
        }
    }
}

__global__ void unpackParticles(int startDstId, BufferOffsetsSizesWrap dataWrap,
                                ParticlePackerHandler packer)
{
    const int bufId = blockIdx.x;

    const int numElements = dataWrap.sizes[bufId];

    for (int pid = threadIdx.x; pid < numElements; pid += blockDim.x)
    {
        const int dstId = startDstId + dataWrap.offsets[bufId] + pid;
        const auto buffer = dataWrap.getBuffer(bufId);
        
        packer.particles.unpack(pid, dstId, buffer, numElements);
    }
}

} // namespace ParticleRedistributorKernels

//===============================================================================================
// Member functions
//===============================================================================================

ParticleRedistributor::ParticleRedistributor() = default;
ParticleRedistributor::~ParticleRedistributor() = default;

bool ParticleRedistributor::needExchange(int id)
{
    return !particles[id]->redistValid;
}

void ParticleRedistributor::attach(ParticleVector *pv, CellList *cl)
{
    int id = particles.size();
    particles.push_back(pv);
    cellLists.push_back(cl);

    if (dynamic_cast<PrimaryCellList*>(cl) == nullptr)
        die("Redistributor (for %s) must be used with a primary cell-list", pv->name.c_str());

    PackPredicate predicate = [](const DataManager::NamedChannelDesc& namedDesc)
    {
        return (namedDesc.second->persistence == DataManager::PersistenceMode::Active) ||
            namedDesc.first == ChannelNames::positions;
    };

    auto packer = std::make_unique<ParticlePacker>(predicate);
    auto helper = std::make_unique<ExchangeHelper>(pv->name, id, packer.get());

    packers.push_back(std::move(packer));
    helpers.push_back(std::move(helper));

    info("Particle redistributor takes pv '%s'", pv->name.c_str());
}

void ParticleRedistributor::prepareSizes(int id, cudaStream_t stream)
{
    auto pv = particles[id];
    auto cl = cellLists[id];
    auto helper = helpers[id].get();
    auto packer = packers[id].get();
    auto lpv = pv->local();
    
    debug2("Counting leaving particles of '%s'", pv->name.c_str());

    helper->send.sizes.clear(stream);

    packer->update(lpv, stream);

    if (lpv->size() > 0)
    {
        const int maxdim = std::max({cl->ncells.x, cl->ncells.y, cl->ncells.z});
        const int nthreads = 64;
        const dim3 nblocks = dim3(getNblocks(maxdim*maxdim, nthreads), 6, 1);

        SAFE_KERNEL_LAUNCH(
            ParticleRedistributorKernels::getExitingParticles<PackMode::Query>,
            nblocks, nthreads, 0, stream,
            cl->cellInfo(), cl->getView<PVview>(),
            pv->state->domain, packer->handler(),
            helper->wrapSendData() );
    }
    helper->computeSendOffsets_Dev2Dev(stream);
}

void ParticleRedistributor::prepareData(int id, cudaStream_t stream)
{
    auto pv = particles[id];
    auto cl = cellLists[id];
    auto helper = helpers[id].get();
    auto packer = packers[id].get();

    debug2("Downloading %d leaving particles of '%s'",
           helper->send.offsets[helper->nBuffers], pv->name.c_str());

    if (pv->local()->size() > 0)
    {
        const int maxdim = std::max({cl->ncells.x, cl->ncells.y, cl->ncells.z});
        const int nthreads = 64;
        const dim3 nblocks = dim3(getNblocks(maxdim*maxdim, nthreads), 6, 1);
        
        helper->resizeSendBuf();
        
        // Sizes will still remain on host, no need to download again
        helper->send.sizes.clearDevice(stream);
        
        SAFE_KERNEL_LAUNCH(
            ParticleRedistributorKernels::getExitingParticles<PackMode::Pack>,
            nblocks, nthreads, 0, stream,
            cl->cellInfo(), cl->getView<PVview>(),
            pv->state->domain, packer->handler(),
            helper->wrapSendData() );
    }
}

void ParticleRedistributor::combineAndUploadData(int id, cudaStream_t stream)
{
    auto pv = particles[id];
    auto helper = helpers[id].get();
    auto packer = packers[id].get();
    auto lpv = pv->local();
    
    int oldSize = lpv->size();
    int totalRecvd = helper->recv.offsets[helper->nBuffers];
    lpv->resize(oldSize + totalRecvd, stream);

    if (totalRecvd > 0)
    {
        const int nthreads = 64;
        const int nblocks  = helper->nBuffers - 1;

        packer->update(lpv, stream);
        
        SAFE_KERNEL_LAUNCH(
            ParticleRedistributorKernels::unpackParticles,
            nblocks, nthreads, 0, stream,
            oldSize, helper->wrapRecvData(), packer->handler());

        // Particles may have migrated, rebuild cell-lists
        pv->cellListStamp++;
    }

    pv->redistValid = true;
}
