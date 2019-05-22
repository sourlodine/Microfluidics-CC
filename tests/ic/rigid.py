#!/usr/bin/env python

import numpy as np
import ymero as ymr

ranks  = (1, 1, 1)
domain = [4., 6., 8.]

u = ymr.ymero(ranks, tuple(domain), dt=0, debug_level=3, log_filename='log')

a=(0.1, 0.2, 0.3)

coords = [[-a[0], -a[1], -a[2]],
          [-a[0], -a[1],  a[2]],
          [-a[0],  a[1], -a[2]],
          [-a[0],  a[1],  a[2]],
          [ a[0],  a[1], -a[2]],
          [ a[0],  a[1],  a[2]]]

com_q = [[ 1., 0., 0.,    1.0, 0.0, 0.0, 0.0],
         [ 3., 0., 0.,    1.0, 2.0, 0.0, 0.0],
         [-1., 0., 0.,    1.0, 0.0, 3.0, 0.0], # out of the domain
         [ 2., 0., 0.,    1.0, 0.0, 0.0, 1.0]]

pv = ymr.ParticleVectors.RigidEllipsoidVector('ellipsoid', mass=1, object_size=len(coords), semi_axes=a)
ic = ymr.InitialConditions.Rigid(com_q=com_q, coords=coords)
u.registerParticleVector(pv=pv, ic=ic)

u.run(2)

if pv:
    icpos = pv.getCoordinates()
    icvel = pv.getVelocities()
    np.savetxt("pos.ic.txt", icpos)
    np.savetxt("vel.ic.txt", icvel)
    

# TEST: ic.rigid
# cd ic
# rm -rf pos*.txt vel*.txt
# ymr.run --runargs "-n 2" ./rigid.py > /dev/null
# paste pos.ic.txt vel.ic.txt | LC_ALL=en_US.utf8 sort > ic.out.txt
