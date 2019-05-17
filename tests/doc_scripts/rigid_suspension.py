#!/usr/bin/env python

import ymero as ymr
import numpy as np
import trimesh

dt = 0.001
rc = 1.0
mass = 1.0
density = 10

m = trimesh.load("sphere_mesh.off");
inertia = [row[i] for i, row in enumerate(m.moment_inertia)]

ranks  = (1, 1, 1)
domain = (16, 8, 8)

u = ymr.ymero(ranks, domain, dt, debug_level=3, log_filename='log', no_splash=True)

pv_solvent = ymr.ParticleVectors.ParticleVector('solvent', mass)
ic_solvent = ymr.InitialConditions.Uniform(density)

dpd = ymr.Interactions.DPD('dpd', rc, a=10.0, gamma=10.0, kbt=0.01, power=0.5)
# repulsive LJ to avoid overlap between spheres
cnt = ymr.Interactions.LJ('cnt', rc, epsilon=0.35, sigma=0.8, max_force=400.0)

vv = ymr.Integrators.VelocityVerlet_withPeriodicForce('vv', force=1.0, direction="x")

com_q = [[2.0, 6.0, 5.0,   1.0, 0.0, 0.0, 0.0],
         [6.0, 7.0, 5.0,   1.0, 0.0, 0.0, 0.0],
         [10., 6.0, 5.0,   1.0, 0.0, 0.0, 0.0],
         [4.0, 2.0, 4.0,   1.0, 0.0, 0.0, 0.0],
         [8.0, 3.0, 2.0,   1.0, 0.0, 0.0, 0.0]]

coords = np.loadtxt("rigid_coords.txt").tolist()
mesh = ymr.ParticleVectors.Mesh(m.vertices.tolist(), m.faces.tolist())

pv_rigid = ymr.ParticleVectors.RigidObjectVector('spheres', mass, inertia, len(coords), mesh)
ic_rigid = ymr.InitialConditions.Rigid(com_q, coords)
vv_rigid = ymr.Integrators.RigidVelocityVerlet("vv_rigid")

u.registerParticleVector(pv_solvent, ic_solvent)
u.registerIntegrator(vv)
u.setIntegrator(vv, pv_solvent)

u.registerParticleVector(pv_rigid, ic_rigid)
u.registerIntegrator(vv_rigid)
u.setIntegrator(vv_rigid, pv_rigid)

u.registerInteraction(dpd)
u.registerInteraction(cnt)
u.setInteraction(dpd, pv_solvent, pv_solvent)
u.setInteraction(dpd, pv_solvent, pv_rigid)
u.setInteraction(cnt, pv_rigid, pv_rigid)

# we need to remove the solvent particles inside the rigid objects
belonging_checker = ymr.BelongingCheckers.Mesh("mesh checker")
u.registerObjectBelongingChecker(belonging_checker, pv_rigid)
u.applyObjectBelongingChecker(belonging_checker, pv_solvent, correct_every=0, inside="none", outside="")

# apply bounce back
bb = ymr.Bouncers.Mesh("bounce_rigid")
u.registerBouncer(bb)
u.setBouncer(bb, pv_rigid, pv_solvent)

# dump the mesh every 200 steps in ply format to the folder 'ply/'
u.registerPlugins(ymr.Plugins.createDumpMesh("mesh_dump", pv_rigid, 200, "ply/"))

u.run(10000)
