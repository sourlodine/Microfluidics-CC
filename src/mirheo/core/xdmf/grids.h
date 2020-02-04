#pragma once

#include "channel.h"

#include <extern/pugixml/src/pugixml.hpp>

#include <cuda_runtime.h>
#include <memory>
#include <mpi.h>
#include <string>
#include <vector>

namespace mirheo
{

namespace XDMF
{
class GridDims
{
public:
    virtual ~GridDims() = default;
        
    virtual std::vector<hsize_t> getLocalSize()  const = 0;
    virtual std::vector<hsize_t> getGlobalSize() const = 0;
    virtual std::vector<hsize_t> getOffsets()    const = 0;

    bool localEmpty()   const;
    bool globalEmpty()  const;
    int getDims()       const;
};
    
class Grid
{
public:
    virtual const GridDims* getGridDims()                                           const = 0; 
    virtual std::string getCentering()                                              const = 0;
                                                                                       
    virtual void writeToHDF5(hid_t file_id, MPI_Comm comm)                          const = 0;
    virtual pugi::xml_node writeToXMF(pugi::xml_node node, std::string h5filename)  const = 0;

    virtual void readFromXMF(const pugi::xml_node &node, std::string &h5filename)         = 0;
    virtual void splitReadAccess(MPI_Comm comm, int chunkSize=1)                          = 0;
    virtual void readFromHDF5(hid_t file_id, MPI_Comm comm)                               = 0;        
        
    virtual ~Grid() = default;
};
    
class UniformGrid : public Grid
{
protected:
        
    class UniformGridDims : public GridDims
    {
    public:
        UniformGridDims(int3 localSize, MPI_Comm cartComm);
            
        std::vector<hsize_t> getLocalSize()  const override;
        std::vector<hsize_t> getGlobalSize() const override;
        std::vector<hsize_t> getOffsets()    const override;

    private:
        std::vector<hsize_t> localSize_;
        std::vector<hsize_t> globalSize_;
        std::vector<hsize_t> offsets_;
    };
            
public:
    const UniformGridDims* getGridDims()                                    const override;        
    std::string getCentering()                                              const override;
                                                                               
    void writeToHDF5(hid_t file_id, MPI_Comm comm)                          const override;
    pugi::xml_node writeToXMF(pugi::xml_node node, std::string h5filename)  const override;
        
    void readFromXMF(const pugi::xml_node &node, std::string &h5filename)         override;
    void splitReadAccess(MPI_Comm comm, int chunkSize = 1)                        override;        
    void readFromHDF5(hid_t file_id, MPI_Comm comm)                               override;
        
    UniformGrid(int3 localSize, real3 h, MPI_Comm cartComm);
        
private:
    UniformGridDims dims_;
    std::vector<real> spacing_;
};
    
        
class VertexGrid : public Grid
{
protected:
        
    class VertexGridDims : public GridDims
    {
    public:
        VertexGridDims(long nLocal, MPI_Comm comm);
            
        std::vector<hsize_t> getLocalSize()  const override;
        std::vector<hsize_t> getGlobalSize() const override;
        std::vector<hsize_t> getOffsets()    const override;

        hsize_t getNLocal()  const;
        void setNLocal(hsize_t n);

        hsize_t getNGlobal()  const;
        void setNGlobal(hsize_t n);

        void setOffset(hsize_t n);

    private:
        hsize_t nLocal_, nGlobal_, offset_;
    };

public:
    
    VertexGrid(std::shared_ptr<std::vector<real3>> positions, MPI_Comm comm);
    
    const VertexGridDims* getGridDims()                                     const override;        
    std::string getCentering()                                              const override;
                                                                               
    void writeToHDF5(hid_t file_id, MPI_Comm comm)                          const override;
    pugi::xml_node writeToXMF(pugi::xml_node node, std::string h5filename)  const override;
        
    void readFromXMF(const pugi::xml_node &node, std::string &h5filename)         override;
    void splitReadAccess(MPI_Comm comm, int chunkSize = 1)                        override;
    void readFromHDF5(hid_t file_id, MPI_Comm comm)                               override;
        
private:
    
    static const std::string positionChannelName_;
    VertexGridDims dims_;

    std::shared_ptr<std::vector<real3>> positions_;

    virtual void _writeTopology(pugi::xml_node& topoNode, const std::string& h5filename) const;
};

class TriangleMeshGrid : public VertexGrid
{
public:
    TriangleMeshGrid(std::shared_ptr<std::vector<real3>> positions, std::shared_ptr<std::vector<int3>> triangles, MPI_Comm comm);
    
    void writeToHDF5(hid_t file_id, MPI_Comm comm) const override;    
        
private:
    static const std::string triangleChannelName_;
    VertexGridDims dimsTriangles_;
    std::shared_ptr<std::vector<int3>> triangles_;

    void _writeTopology(pugi::xml_node& topoNode, const std::string& h5filename) const override;
};

} // namespace XDMF

} // namespace mirheo
