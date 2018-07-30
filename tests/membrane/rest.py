#!/usr/bin/env python3

import sys
import numpy as np

sys.path.insert(0, "..")
from common.context import udevicex as udx
from common.membrane_params import set_lina

dt = 0.001

ranks  = (1, 1, 1)
domain = (12, 8, 10)

u = udx.udevicex(ranks, domain, debug_level=2, log_filename='log')

mesh_rbc = udx.ParticleVectors.MembraneMesh("rbc_mesh.off")
pv_rbc   = udx.ParticleVectors.MembraneVector("rbc", mass=1.0, object_size=498, mesh=mesh_rbc)
ic_rbc   = udx.InitialConditions.Membrane("rbcs-ic.txt")
u.registerParticleVector(pv_rbc, ic_rbc)

prm_rbc = udx.Interactions.MembraneParameters()

if prm_rbc:
    set_lina(1.0, prm_rbc)

int_rbc = udx.Interactions.MembraneForces("int_rbc", prm_rbc, stressFree=False)
vv = udx.Integrators.VelocityVerlet('vv', dt)
u.registerIntegrator(vv)
u.setIntegrator(vv, pv_rbc)
u.registerInteraction(int_rbc)
u.setInteraction(int_rbc, pv_rbc, pv_rbc)

# dump_mesh = udx.Plugins.createDumpMesh("mesh_dump", pv_rbc, 500, "ply/")
# u.registerPlugins(dump_mesh)

u.run(5000)

if pv_rbc:
    rbc_pos = pv_rbc.getCoordinates()
    np.savetxt("pos.rbc.txt", rbc_pos)

# nTEST: membrane.rest
# cd membrane
# cp ../../data/rbc_mesh.off .
# echo "6.0 4.0 5.0 1.0 0.0 0.0 0.0" > rbcs-ic.txt
# cp ../../data/rbc_mesh.off .
# udx.run -n 2 ./rest.py > /dev/null
# mv pos.rbc.txt pos.rbc.out.txt 
