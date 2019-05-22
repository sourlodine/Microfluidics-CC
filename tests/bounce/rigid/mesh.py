#!/usr/bin/env python

import numpy as np
import ymero as ymr
import argparse, trimesh

parser = argparse.ArgumentParser()
parser.add_argument('--file', type=str)
parser.add_argument('--vis', action='store_true', default=False)
args = parser.parse_args()

ranks  = (1, 1, 1)
domain = [8., 8., 8.]

dt   = 0.001

u = ymr.ymero(ranks, tuple(domain), dt, debug_level=3, log_filename='log', no_splash=True)

nparts = 100
pos = np.random.normal(loc   = [0.5, 0.5 * domain[1] + 1.0, 0.5 * domain[2]],
                       scale = [0.1, 0.3, 0.3],
                       size  = (nparts, 3))

vel = np.random.normal(loc   = [1.0, 0., 0.],
                       scale = [0.1, 0.01, 0.01],
                       size  = (nparts, 3))


pvSolvent = ymr.ParticleVectors.ParticleVector('pv', mass = 1)
icSolvent = ymr.InitialConditions.FromArray(pos=pos.tolist(), vel=vel.tolist())
vvSolvent = ymr.Integrators.VelocityVerlet('vv')
u.registerParticleVector(pvSolvent, icSolvent)
u.registerIntegrator(vvSolvent)
u.setIntegrator(vvSolvent, pvSolvent)


com_q = [[0.5 * domain[0], 0.5 * domain[1], 0.5 * domain[2],   0.7071, 0, 0.7071, 0]]
coords = [[-2., -2., -2.],
          [ 2.,  2.,  2.]] # fake coords: don t need inside particles

m = trimesh.load(args.file);
inertia = [row[i] for i, row in enumerate(m.moment_inertia)]

mesh    = ymr.ParticleVectors.Mesh(m.vertices.tolist(), m.faces.tolist())
pvRigid = ymr.ParticleVectors.RigidObjectVector('rigid', mass=100, inertia=inertia, object_size=len(coords), mesh=mesh)


icRigid = ymr.InitialConditions.Rigid(com_q=com_q, coords=coords)
vvRigid = ymr.Integrators.RigidVelocityVerlet("vvRigid")
u.registerParticleVector(pv=pvRigid, ic=icRigid)
u.registerIntegrator(vvRigid)
u.setIntegrator(vvRigid, pvRigid)

bb = ymr.Bouncers.Mesh("bounceRigid", kbt=0.0)
u.registerBouncer(bb)
u.setBouncer(bb, pvRigid, pvSolvent)

dumpEvery=500

if args.vis:
    u.registerPlugins(ymr.Plugins.createDumpParticles('partDump', pvSolvent, dumpEvery, [], 'h5/solvent-'))
    u.registerPlugins(ymr.Plugins.createDumpMesh("mesh_dump", pvRigid, dumpEvery, path="ply/"))

u.registerPlugins(ymr.Plugins.createDumpObjectStats("rigStats", ov=pvRigid, dump_every=dumpEvery, path="stats"))

u.run(5000)
    

# nTEST: bounce.rigid.mesh
# set -eu
# cd bounce/rigid
# rm -rf stats rigid.out.txt
# f="../../../data/rbc_mesh.off"
# rm -rf pos*.txt vel*.txt
# ymr.run --runargs "-n 2" ./mesh.py --file $f
# cat stats/rigid.txt | awk '{print $2, $15, $9}' > rigid.out.txt
