#pragma once

#include <core/domain.h>
#include <core/pvs/particle_vector.h>
#include <core/utils/type_shift.h>
#include <core/utils/type_map.h>

#include <mpi.h>
#include <tuple>
#include <vector>

namespace RestartHelpers
{
constexpr int InvalidProc = -1;
constexpr int tag = 4243;

using VarVector = mpark::variant<
#define MAKE_WRAPPER(a) std::vector<a>
    TYPE_TABLE_COMMA(MAKE_WRAPPER)
#undef MAKE_WRAPPER
    >;

struct NamedData
{
    std::string name;
    VarVector data;
};

using ListData = std::vector<NamedData>;
using ExchMap  = std::vector<int>;

ListData readData(const std::string& filename, MPI_Comm comm, int chunkSize);

template<typename T>
std::vector<T> extractChannel(const std::string& name, ListData& channels)
{
    using VecType = std::vector<T>;

    for (auto it = channels.begin(); it != channels.end(); ++it)
    {
        if (it->name != name) continue;

        if (mpark::holds_alternative<VecType>(it->data))
        {
            VecType v {std::move(mpark::get<VecType>(it->data))};
            channels.erase(it);
            return v;
        }
        else
        {
            mpark::visit([&](const auto& vec)
            {
                using VecType = typename std::remove_reference<decltype(vec)>::type::value_type;
                die ("could not retrieve channel '%s' with given type: got %s instead of %s",
                     name.c_str(), typeid(VecType).name(), typeid(T).name());
            }, it->data);
        }
    }
    die ("could not find channel '%s'", name.c_str());
    return {};
}

ExchMap getExchangeMap(MPI_Comm comm, const DomainInfo domain,
                       int objSize, const std::vector<float3>& positions);

std::tuple<std::vector<float4>, std::vector<float4>>
combinePosVelIds(const std::vector<float3>& pos,
                 const std::vector<float3>& vel,
                 const std::vector<int64_t>& ids);

std::vector<RigidMotion>
combineMotions(const std::vector<float3>& pos,
               const std::vector<RigidReal4>& quaternion,
               const std::vector<RigidReal3>& vel,
               const std::vector<RigidReal3>& omega,
               const std::vector<RigidReal3>& force,
               const std::vector<RigidReal3>& torque);

void copyShiftCoordinates(const DomainInfo &domain, const std::vector<float4>& pos,
                          const std::vector<float4>& vel, LocalParticleVector *local);


int getLocalNumElementsAfterExchange(MPI_Comm comm, const ExchMap& map);

namespace details
{
template <typename T>
static std::vector<std::vector<T>> splitData(const ExchMap& map, int chunkSize,
                                             const std::vector<T>& data, int numProcs)
{
    std::vector<std::vector<T>> bufs(numProcs);
    
    for (int i = 0; i < map.size(); ++i)
    {
        int procId = map[i];

        if (procId == InvalidProc) continue;

        bufs[procId].insert(bufs[procId].end(),
                            data.begin() +  i      * chunkSize,
                            data.begin() + (i + 1) * chunkSize);
    }

    return bufs;
}

template<typename T>
static std::vector<MPI_Request> sendData(const std::vector<std::vector<T>>& sendBufs,
                                         MPI_Comm comm)
{
    std::vector<MPI_Request> reqs;
    
    for (int i = 0; i < sendBufs.size(); ++i)
    {
        MPI_Request req;
        debug3("Sending %d elements to rank %d", sendBufs[i].size(), i);
        MPI_Check( MPI_Isend(sendBufs[i].data(), sendBufs[i].size() * sizeof(T),
                             MPI_BYTE, i, tag, comm, &req) );
        reqs.push_back(req);
    }
    return reqs;
}

template <typename T>
static std::vector<T> recvData(int size, MPI_Comm comm)
{
    std::vector<T> allData;
    for (int i = 0; i < size; ++i)
    {
        MPI_Status status;
        int sizeBytes, size;
        std::vector<T> recvBuf;
        
        MPI_Check( MPI_Probe(MPI_ANY_SOURCE, tag, comm, &status) );
        MPI_Check( MPI_Get_count(&status, MPI_BYTE, &sizeBytes) );

        size = sizeBytes / sizeof(T);

        if (size * sizeof(T) != sizeBytes)
            die("unexpected received size");
        
        recvBuf.resize(size);

        debug3("Receiving %d elements from %d", size, status.MPI_SOURCE);
        MPI_Check( MPI_Recv(recvBuf.data(), sizeBytes, MPI_BYTE,
                            status.MPI_SOURCE, tag, comm, MPI_STATUS_IGNORE) );

        allData.insert(allData.end(), recvBuf.begin(), recvBuf.end());
    }
    return allData;
}
} // namespace details

template<typename T>
static void exchangeData(MPI_Comm comm, const ExchMap& map,
                         std::vector<T>& data, int chunkSize = 1)
{
    int numProcs;
    MPI_Check( MPI_Comm_size(comm, &numProcs) );
            
    auto sendBufs = details::splitData(map, chunkSize, data, numProcs);
    auto sendReqs = details::sendData(sendBufs, comm);
    data          = details::recvData<T>(numProcs, comm);

    MPI_Check( MPI_Waitall(sendReqs.size(), sendReqs.data(), MPI_STATUSES_IGNORE) );
}

void exchangeListData(MPI_Comm comm, const ExchMap& map, ListData& listData, int chunkSize = 1);

template<typename Container>
static void shiftElementsGlobal2Local(Container& data, const DomainInfo domain)
{
    auto shift = domain.global2local({0.f, 0.f, 0.f});
    for (auto& d : data) TypeShift::apply(d, shift);    
}

} // namespace RestartHelpers
