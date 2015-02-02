#include <sys/stat.h>
#include <sys/time.h>

#ifndef NO_H5
#include <hdf5.h>
#endif

#ifndef NO_H5PART
#include <H5Part.h>
#endif

#include <string>
#include <sstream>
#include <vector>

#include "io.h"

using namespace std;

void xyz_dump(MPI_Comm comm, const char * filename, const char * particlename, Particle * particles, int n, int L, bool append)
{
    int rank;
    MPI_CHECK( MPI_Comm_rank(comm, &rank) );
    
    int dims[3], periods[3], coords[3];
    MPI_CHECK( MPI_Cart_get(comm, 3, dims, periods, coords) );

    const int nlocal = n;
    MPI_CHECK( MPI_Reduce(rank == 0 ? MPI_IN_PLACE : &n, &n, 1, MPI_INT, MPI_SUM, 0, comm) );
    
    bool filenotthere;
    if (rank == 0)
	filenotthere = access(filename, F_OK ) == -1;

    MPI_CHECK( MPI_Bcast(&filenotthere, 1, MPI_INT, 0, comm) );

    append &= !filenotthere;

    MPI_File f;
    MPI_CHECK( MPI_File_open(comm, filename , MPI_MODE_WRONLY | (append ? MPI_MODE_APPEND : MPI_MODE_CREATE), MPI_INFO_NULL, &f) );

    if (!append)
	MPI_CHECK( MPI_File_set_size (f, 0));
	
    MPI_Offset base;
    MPI_CHECK( MPI_File_get_position(f, &base));
	
    std::stringstream ss;

    if (rank == 0)
    {
	ss <<  n << "\n";
	ss << particlename << "\n";

	printf("total number of particles: %d\n", n);
    }
    
    for(int i = 0; i < nlocal; ++i)
	ss << rank << " " 
	   << (particles[i].x[0] + L / 2 + coords[0] * L) << " "
	   << (particles[i].x[1] + L / 2 + coords[1] * L) << " "
	   << (particles[i].x[2] + L / 2 + coords[2] * L) << "\n";

    string content = ss.str();
	
    int len = content.size();
    int offset = 0;
    MPI_CHECK( MPI_Exscan(&len, &offset, 1, MPI_INTEGER, MPI_SUM, comm)); 
	
    MPI_Status status;
	
    MPI_CHECK( MPI_File_write_at_all(f, base + offset, const_cast<char *>(content.c_str()), len, MPI_CHAR, &status));
	
    MPI_CHECK( MPI_File_close(&f));
}

void _write_bytes(const void * const ptr, const int nbytes, MPI_File f, MPI_Comm comm)
{
    MPI_Offset base;
    MPI_CHECK( MPI_File_get_position(f, &base));
    
    int offset = 0;
    MPI_CHECK( MPI_Exscan(&nbytes, &offset, 1, MPI_INTEGER, MPI_SUM, comm)); 
	
    MPI_Status status;
	
    MPI_CHECK( MPI_File_write_at_all(f, base + offset, ptr, nbytes, MPI_CHAR, &status));

    int ntotal = 0;
    MPI_CHECK( MPI_Allreduce(&nbytes, &ntotal, 1, MPI_INT, MPI_SUM, comm) );
    
    MPI_CHECK( MPI_File_seek(f, ntotal, MPI_SEEK_CUR));
}

void ply_dump(MPI_Comm comm, const char * filename,
	      int (*mesh_indices)[3], const int ninstances, const int ntriangles_per_instance,
	      Particle * _particles, int nvertices_per_instance, int L, bool append)
{
    std::vector<Particle> particles(_particles, _particles + ninstances * nvertices_per_instance);
    
    int rank;
    MPI_CHECK( MPI_Comm_rank(comm, &rank) );
    
    int dims[3], periods[3], coords[3];
    MPI_CHECK( MPI_Cart_get(comm, 3, dims, periods, coords) );

    int NPOINTS = 0;
    const int n = particles.size();
    MPI_CHECK( MPI_Reduce(&n, &NPOINTS, 1, MPI_INT, MPI_SUM, 0, comm) );

    const int ntriangles = ntriangles_per_instance * ninstances;
    int NTRIANGLES = 0;
    MPI_CHECK( MPI_Reduce(&ntriangles, &NTRIANGLES, 1, MPI_INT, MPI_SUM, 0, comm) );
    
    MPI_File f;
    MPI_CHECK( MPI_File_open(comm, filename , MPI_MODE_WRONLY | (append ? MPI_MODE_APPEND : MPI_MODE_CREATE), MPI_INFO_NULL, &f) );

    if (!append)
	MPI_CHECK( MPI_File_set_size (f, 0));
	
    std::stringstream ss;

    if (rank == 0)
    {
	ss <<  "ply\n";
	ss <<  "format binary_little_endian 1.0\n";
	ss <<  "element vertex " << NPOINTS << "\n";
	ss <<  "property float x\nproperty float y\nproperty float z\n";
	ss <<  "property float u\nproperty float v\nproperty float w\n"; 
	//ss <<  "property float xnormal\nproperty float ynormal\nproperty float znormal\n";
	ss <<  "element face " << NTRIANGLES << "\n";
	ss <<  "property list int int vertex_index\n";
	ss <<  "end_header\n";
    } 
    
    string content = ss.str();
    
    _write_bytes(content.c_str(), content.size(), f, comm);
    
    for(int i = 0; i < n; ++i)
	for(int c = 0; c < 3; ++c)
	    particles[i].x[c] += L / 2 + coords[c] * L;

    _write_bytes(&particles.front(), sizeof(Particle) * n, f, comm);

    int poffset = 0;
    
    MPI_CHECK( MPI_Exscan(&n, &poffset, 1, MPI_INTEGER, MPI_SUM, comm));

    std::vector<int> buf;

    for(int j = 0; j < ninstances; ++j)
	for(int i = 0; i < ntriangles_per_instance; ++i)
	{
	    int primitive[4] = { 3,
				 poffset + nvertices_per_instance * j + mesh_indices[i][0],
				 poffset + nvertices_per_instance * j + mesh_indices[i][1],
				 poffset + nvertices_per_instance * j + mesh_indices[i][2] };
	    
	    buf.insert(buf.end(), primitive, primitive + 4);
	}

    _write_bytes(&buf.front(), sizeof(int) * buf.size(), f, comm);
    
    MPI_CHECK( MPI_File_close(&f));
}

H5PartDump::H5PartDump(const string fname, MPI_Comm cartcomm, const int L):
    cartcomm(cartcomm), fname(fname), tstamp(0)
{
#ifndef NO_H5PART
    int dims[3], periods[3], coords[3];
    MPI_CHECK( MPI_Cart_get(cartcomm, 3, dims, periods, coords) );

    for(int c = 0; c < 3; ++c)
	origin[c] = L / 2 + coords[c] * L;

    H5PartFile * f = H5PartOpenFileParallel(fname.c_str(), H5PART_WRITE, cartcomm);

    assert(f != NULL);

    handler = f;
#endif
}

void H5PartDump::dump(Particle * host_particles, int n)
{
#ifndef NO_H5PART
    H5PartFile * f = (H5PartFile *)handler;

    H5PartSetStep(f, tstamp);

    H5PartSetNumParticles(f, n);

    string labels[] = {"x", "y", "z"};

    for(int c = 0; c < 3; ++c)
    {
	vector<float> data(n);

	for(int i = 0; i < n; ++i)
	    data[i] = host_particles[i].x[c] + origin[c];

	H5PartWriteDataFloat32(f, labels[c].c_str(), &data.front());
    }

    tstamp++;
#endif
}
    
H5PartDump::~H5PartDump()
{
#ifndef NO_H5PART
    H5PartFile * f = (H5PartFile *)handler;

    H5PartCloseFile(f);
#endif
}

void H5FieldDump::_xdmf_header(FILE * xmf)
{
    fprintf(xmf, "<?xml version=\"1.0\" ?>\n");
    fprintf(xmf, "<!DOCTYPE Xdmf SYSTEM \"Xdmf.dtd\" []>\n");
    fprintf(xmf, "<Xdmf Version=\"2.0\">\n");
    fprintf(xmf, " <Domain>\n");
}

void H5FieldDump::_xdmf_grid(FILE * xmf, float time, 
			     const char * const h5path, const char * const * channelnames, int nchannels)
{
    fprintf(xmf, "   <Grid Name=\"mesh\" GridType=\"Uniform\">\n");
    fprintf(xmf, "     <Time Value=\"%.f\"/>\n", time);
    fprintf(xmf, "     <Topology TopologyType=\"3DCORECTMesh\" Dimensions=\"%d %d %d\"/>\n", 
	    1 + (int)globalsize[2], 1 + (int)globalsize[1], 1 + (int)globalsize[0]);
    
    fprintf(xmf, "     <Geometry GeometryType=\"ORIGIN_DXDYDZ\">\n");
    fprintf(xmf, "       <DataItem Name=\"Origin\" Dimensions=\"3\" NumberType=\"Float\" Precision=\"4\" Format=\"XML\">\n");
    fprintf(xmf, "        %e %e %e\n", 0.0, 0.0, 0.0);
    fprintf(xmf, "       </DataItem>\n");
    fprintf(xmf, "       <DataItem Name=\"Spacing\" Dimensions=\"3\" NumberType=\"Float\" Precision=\"4\" Format=\"XML\">\n");
    
    const float h = 1;
    fprintf(xmf, "        %e %e %e\n", h, h, h);
    fprintf(xmf, "       </DataItem>\n");
    fprintf(xmf, "     </Geometry>\n");
    
    for(int ichannel = 0; ichannel < nchannels; ++ichannel)
    {
	fprintf(xmf, "     <Attribute Name=\"%s\" AttributeType=\"Scalar\" Center=\"Cell\">\n", channelnames[ichannel]);    
	fprintf(xmf, "       <DataItem Dimensions=\"%d %d %d 1\" NumberType=\"Float\" Precision=\"4\" Format=\"HDF\">\n", 
		(int)globalsize[2], (int)globalsize[1], (int)globalsize[0]);
	
	fprintf(xmf, "        %s:/%s\n", h5path, channelnames[ichannel]);
	
	fprintf(xmf, "       </DataItem>\n");
	fprintf(xmf, "     </Attribute>\n");	
    }
    
    fprintf(xmf, "   </Grid>\n");
    }

void H5FieldDump::_xdmf_epilogue(FILE * xmf)
{
    fprintf(xmf, " </Domain>\n");
    fprintf(xmf, "</Xdmf>\n");
}

void H5FieldDump::_write_fields(const char * const path2h5,
				const float * const channeldata[], const char * const * const channelnames, const int nchannels, 
				MPI_Comm cartcomm, const float time)
{
#ifndef NO_H5
    int nranks[3], periods[3], myrank[3];
    MPI_CHECK( MPI_Cart_get(cartcomm, 3, nranks, periods, myrank) );
    
    id_t plist_id_access = H5Pcreate(H5P_FILE_ACCESS);
    H5Pset_fapl_mpio(plist_id_access, cartcomm, MPI_INFO_NULL);
    
    hid_t file_id = H5Fcreate(path2h5, H5F_ACC_TRUNC, H5P_DEFAULT, plist_id_access);
    H5Pclose(plist_id_access);
    
    hsize_t globalsize[4] = {nranks[2] * L, nranks[1] * L, nranks[0] * L, 1};    
    hid_t filespace_simple = H5Screate_simple(4, globalsize, NULL);
    
    for(int ichannel = 0; ichannel < nchannels; ++ichannel)
    {
	hid_t dset_id = H5Dcreate(file_id, channelnames[ichannel], H5T_NATIVE_FLOAT, filespace_simple, H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);
	id_t plist_id = H5Pcreate(H5P_DATASET_XFER);
	
	H5Pset_dxpl_mpio(plist_id, H5FD_MPIO_COLLECTIVE);
	
	hsize_t start[4] = { myrank[2] * L, myrank[1] * L, myrank[0] * L, 0};
	hsize_t extent[4] = { L, L, L,  1};
	hid_t filespace = H5Dget_space(dset_id);
	H5Sselect_hyperslab(filespace, H5S_SELECT_SET, start, NULL, extent, NULL);
	
	hid_t memspace = H5Screate_simple(4, extent, NULL); 
	herr_t status = H5Dwrite(dset_id, H5T_NATIVE_FLOAT, memspace, filespace, plist_id, channeldata[ichannel]);
	
	H5Sclose(memspace);
	H5Sclose(filespace);
	H5Pclose(plist_id);		
	H5Dclose(dset_id);
    }
    
    H5Sclose(filespace_simple);
    H5Fclose(file_id);

    int rankscalar;
    MPI_CHECK(MPI_Comm_rank(cartcomm, &rankscalar));

    if (!rankscalar)
    {
	char wrapper[256];
	sprintf(wrapper, "%s.xmf", string(path2h5).substr(0, string(path2h5).find_last_of(".h5") - 2).data());
	
	FILE * xmf = fopen(wrapper, "w");
	assert(xmf);
	
	_xdmf_header(xmf);
	_xdmf_grid(xmf, time, string(path2h5).substr(string(path2h5).find_last_of("/") + 1).c_str(), channelnames, nchannels);
	_xdmf_epilogue(xmf);

	fclose(xmf);
    }
#endif // NO_H5
}

H5FieldDump::H5FieldDump(MPI_Comm cartcomm): cartcomm(cartcomm), last_idtimestep(0) 
{
    int dims[3], periods[3], coords[3];
    MPI_CHECK( MPI_Cart_get(cartcomm, 3, dims, periods, coords) );

    for(int c = 0; c < 3; ++c)
	globalsize[c] = L * dims[c];
}

void H5FieldDump::dump_scalarfield(const float * const data, const char * channelname)
{
    char path2h5[512];
    sprintf(path2h5, "h5/%s.h5", channelname);

    _write_fields(path2h5, &data, &channelname, 1, cartcomm, 0);
}

void H5FieldDump::dump(const Particle * const p, const int n, int idtimestep)
{
#ifndef NO_H5
    last_idtimestep = idtimestep;

    const int ncells = L * L * L;

    vector<float> rho(ncells), u[3];

    for(int c = 0; c < 3; ++c)
	u[c].resize(ncells);

    for(int i = 0; i < n; ++i)
    {
	const int cellindex[3] = {
	    (int)floor(p[i].x[0] + L / 2),
	    (int)floor(p[i].x[1] + L / 2),
	    (int)floor(p[i].x[2] + L / 2)
	};

	const int entry = cellindex[0] + L * (cellindex[1] + L * cellindex[2]);

	rho[entry] += 1;

	for(int c = 0; c < 3; ++c)
	    u[c][entry] += p[i].u[c];
    }

    for(int c = 0; c < 3; ++c)
	for(int i = 0; i < ncells; ++i)
	    u[c][i] = rho[i] ? u[c][i] / rho[i] : 0;

    const char * names[] = { "density", "u", "v", "w" };
 
    mkdir("h5", S_IRWXU | S_IRWXG | S_IROTH | S_IXOTH);

    char filepath[512];
    sprintf(filepath, "h5/flowfields-%04d.h5", idtimestep / steps_per_dump);

    float * data[] = { rho.data(), u[0].data(), u[1].data(), u[2].data() };

    _write_fields(filepath, data, names, 4, cartcomm, idtimestep * dt);

#endif // NO_H5
}

H5FieldDump::~H5FieldDump()
{
#ifndef NO_H5

    FILE * xmf = fopen("h5/flowfields-sequence.xmf", "w");

    assert(xmf);

    _xdmf_header(xmf);

    fprintf(xmf, "   <Grid Name=\"TimeSeries\" GridType=\"Collection\" CollectionType=\"Temporal\">\n");

    const char * channelnames[] = { "density", "u", "v", "w" };
    for(int it = 0; it <= last_idtimestep; it += steps_per_dump)
    {  
	char filepath[512];
	sprintf(filepath, "h5/flowfields-%04d.h5", it / steps_per_dump);

	_xdmf_grid(xmf, it * dt,  string(filepath).substr(string(filepath).find_last_of("/") + 1).c_str(), channelnames, 4);
    }

    fprintf(xmf, "   </Grid>\n");

    _xdmf_epilogue(xmf);

    fclose(xmf);

#endif //NO_H5
}
