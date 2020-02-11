#!/usr/bin/env python

import mirheo as mir
import numpy as np
import argparse

parser = argparse.ArgumentParser()
parser.add_argument('--ranks', type=int, nargs=3, required=True)
parser.add_argument('--save-to', type=str, required=True)
parser.add_argument('--load-from', type=str)
args = parser.parse_args()

if not args.load_from:
    u = mir.Mirheo(args.ranks, domain=(4, 6, 8), dt=0.1, debug_level=3, log_filename='log', no_splash=True)

    mesh = mir.ParticleVectors.MembraneMesh('mesh_dummy1.off')
    ov = mir.ParticleVectors.MembraneVector('ov', mesh=mesh, mass=1)
    ic = mir.InitialConditions.Membrane([])
    u.registerParticleVector(ov, ic)

    u.registerPlugins(mir.Plugins.createStats('stats', every=10, filename='stats.txt'))
    u.registerPlugins(mir.Plugins.createDumpMesh('rbcs', ov, dump_every=15, path='ply'))

    u.saveSnapshot(args.save_to)
else:
    u = mir.Mirheo(args.ranks, snapshot=args.load_from, debug_level=3, log_filename='log', no_splash=True)
    u.saveSnapshot(args.save_to)

# TEST: snapshot.plugins
# cd snapshot
# echo rm -rf snapshot1/ snapshot2/
# mir.run --runargs "-n 4" ./plugins.py --ranks 2 1 1 --save-to snapshot1/
# mir.run --runargs "-n 4" ./plugins.py --ranks 2 1 1 --save-to snapshot2/ --load-from snapshot1/
# git --no-pager diff --no-index snapshot1/config.compute.json snapshot2/config.compute.json
# git --no-pager diff --no-index snapshot1/config.post.json snapshot2/config.post.json
# cat snapshot1/config.compute.json snapshot1/config.post.json > snapshot.out.txt
