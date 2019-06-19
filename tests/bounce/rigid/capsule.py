#!/usr/bin/env python

import numpy as np
import ymero as ymr
import argparse

parser = argparse.ArgumentParser()
parser.add_argument('--coords', type=str)
parser.add_argument('--vis', action='store_true', default=False)
args = parser.parse_args()

ranks  = (1, 1, 1)
domain = [16., 16., 16.]

radius = 1.5
length = 5.0

dt   = 0.001

u = ymr.ymero(ranks, tuple(domain), dt, debug_level=3, log_filename='log', no_splash=True)

nparts = 100
pos = np.random.normal(loc   = [0.5, 0.5 * domain[1] + 1.0, 0.5 * domain[2] + 1.5],
                       scale = [0.1, 0.3, 0.3],
                       size  = (nparts, 3))

vel = np.random.normal(loc   = [1.0, 0., 0.],
                       scale = [0.1, 0.01, 0.01],
                       size  = (nparts, 3))


pv_sol = ymr.ParticleVectors.ParticleVector('pv', mass = 1)
ic_sol = ymr.InitialConditions.FromArray(pos.tolist(), vel.tolist())
vv_sol = ymr.Integrators.VelocityVerlet('vv')
u.registerParticleVector(pv_sol, ic_sol)
u.registerIntegrator(vv_sol)
u.setIntegrator(vv_sol, pv_sol)


com_q = [[0.5 * domain[0], 0.5 * domain[1], 0.5 * domain[2],   1., 0, 0, 0]]
coords = np.loadtxt(args.coords).tolist()

if args.vis:
    import trimesh
    cap_mesh = trimesh.creation.capsule(radius = radius, height = length)
    cap_mesh.vertices = cap_mesh.vertices - [0, 0, length/2]
    mesh = ymr.ParticleVectors.Mesh(cap_mesh.vertices.tolist(), cap_mesh.faces.tolist())
    ov_rig = ymr.ParticleVectors.RigidCapsuleVector('capsule', mass=1, object_size=len(coords), radius=radius, length=length, mesh=mesh)
else:
    ov_rig = ymr.ParticleVectors.RigidCapsuleVector('capsule', mass=1, object_size=len(coords), radius=radius, length=length)

ic_rig = ymr.InitialConditions.Rigid(com_q, coords)
vv_rig = ymr.Integrators.RigidVelocityVerlet("capvv")
u.registerParticleVector(ov_rig, ic_rig)
u.registerIntegrator(vv_rig)
u.setIntegrator(vv_rig, ov_rig)


bb = ymr.Bouncers.Capsule("bouncer")
u.registerBouncer(bb)
u.setBouncer(bb, ov_rig, pv_sol)

dump_every = 500

if args.vis:
    u.registerPlugins(ymr.Plugins.createDumpParticles('part_dump', pv_sol, dump_every, [], 'h5/solvent-'))
    u.registerPlugins(ymr.Plugins.createDumpParticles('pcap_dump', ov_rig, dump_every, [], 'h5/rigid-'))
    u.registerPlugins(ymr.Plugins.createDumpMesh("mesh_dump", ov_rig, dump_every, path="ply/"))

u.registerPlugins(ymr.Plugins.createDumpObjectStats("rigStats", ov_rig, dump_every, path="stats"))

u.run(5000)

# nTEST: bounce.rigid.capsule
# set -eu
# cd bounce/rigid
# rm -rf stats rigid.out.txt
# f="pos.txt"
# rho=8.0; R=1.5; L=5.0
# rm -rf pos*.txt vel*.txt
# cp ../../../data/capsule_coords_${rho}_${R}_${L}.txt $f
# ymr.run --runargs "-n 2" ./capsule.py --coords $f
# cat stats/capsule.txt | awk '{print $2, $15, $9}' > rigid.out.txt
