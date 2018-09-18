#!/usr/bin/env python

import udevicex as udx
import numpy as np
import argparse

dt   = 0.001
axes = (1, 2, 3)

ranks  = (1, 1, 1)
domain = (8, 16, 24)

u = udx.udevicex(ranks, domain, debug_level=3, log_filename='log')

com_q = [[domain[0]/2.0, domain[1]/2.0, domain[2]/2.0,  1., 0, 0, 0]]
coords = np.loadtxt('sphere123.txt').tolist()
pvEllipsoid = udx.ParticleVectors.RigidEllipsoidVector('object', mass=1, object_size=len(coords), semi_axes=axes)
icEllipsoid = udx.InitialConditions.Rigid(com_q=com_q, coords=coords)
vvEllipsoid = udx.Integrators.RigidVelocityVerlet("ellvv", dt)

u.registerParticleVector(pv=pvEllipsoid, ic=icEllipsoid)
u.registerIntegrator(vvEllipsoid)
u.setIntegrator(vvEllipsoid, pvEllipsoid)

pv = udx.ParticleVectors.ParticleVector('pv', mass = 1)
u.registerParticleVector(pv, udx.InitialConditions.Uniform(density=8))

dpd = udx.Interactions.DPD('dpd', 1.0, a=2.0, gamma=10.0, kbt=0.1, dt=dt, power=0.5)
u.registerInteraction(dpd)
u.setInteraction(dpd, pv, pv)
u.setInteraction(dpd, pvEllipsoid, pv)

vv = udx.Integrators.VelocityVerlet_withConstForce('vv', dt=dt, force=(0.1, 0, 0))
u.registerIntegrator(vv)
u.setIntegrator(vv, pv)

sampleEvery = 2
dumpEvery   = 1000
binSize     = (1., 1., 1.)

u.registerPlugins(udx.Plugins.createDumpAverageRelative(
    'field', [pv], pvEllipsoid, 0,
    sampleEvery, dumpEvery, binSize, [("velocity", "vector_from_float8")], 'h5/solvent-'))

u.run(5010)


# nTEST: plugins.relative_flow
# set -eu
# cd plugins
# rm -rf h5/
# udx.run --runargs "-n 2" ./relative_flow.py > /dev/null
# udx.avgh5 xy velocity h5/solvent-0000[2-4].h5 >  profile.out.txt
# udx.avgh5 yz velocity h5/solvent-0000[2-4].h5 >> profile.out.txt
# udx.avgh5 zx velocity h5/solvent-0000[2-4].h5 >> profile.out.txt
