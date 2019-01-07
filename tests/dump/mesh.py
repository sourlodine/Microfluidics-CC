#!/usr/bin/env python

import ymero as ymr
import numpy as np
import trimesh, argparse

parser = argparse.ArgumentParser()
parser.add_argument("--readFrom", choices=["off", 'trimesh'])
args = parser.parse_args()


path   = "ply/"
pvname = "rbc"
off    = "rbc_mesh.off"

ranks  = (1, 1, 1)
domain = (12, 8, 10)

u = ymr.ymero(ranks, domain, dt=0, debug_level=3, log_filename='log')

if args.readFrom == "off":
    mesh = ymr.ParticleVectors.MembraneMesh(off)
elif args.readFrom == "trimesh":
    m = trimesh.load(off);
    mesh = ymr.ParticleVectors.MembraneMesh(m.vertices.tolist(), m.faces.tolist())

rbc  = ymr.ParticleVectors.MembraneVector(pvname, mass=1.0, mesh=mesh)
icrbc = ymr.InitialConditions.Membrane([[6.0, 4.0, 5.0,   1.0, 0.0, 0.0, 0.0]])
u.registerParticleVector(pv=rbc, ic=icrbc)

mdump = ymr.Plugins.createDumpMesh("mesh_dump", rbc, 1, path)
u.registerPlugins(mdump)

u.run(3)

if u.isMasterTask():
    mesh = trimesh.load(path + pvname + "_00000.ply")
    np.savetxt("vertices.txt", mesh.vertices, fmt="%g")
    np.savetxt("faces.txt",    mesh.faces,    fmt="%d")

# TEST: dump.mesh
# cd dump
# rm -rf ply/ vertices.txt faces.txt mesh.out.txt 
# cp ../../data/rbc_mesh.off .
# ymr.run --runargs "-n 2" ./mesh.py --readFrom off > /dev/null
# cat vertices.txt faces.txt > mesh.out.txt

# TEST: dump.mesh.fromTrimesh
# cd dump
# rm -rf ply/ vertices.txt faces.txt mesh.out.txt 
# cp ../../data/rbc_mesh.off .
# ymr.run --runargs "-n 2" ./mesh.py --readFrom trimesh > /dev/null
# cat vertices.txt faces.txt > mesh.out.txt
