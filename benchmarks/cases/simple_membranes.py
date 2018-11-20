#!/usr/bin/env python

import argparse, sys, pickle, math
import udevicex as udx
from membrane_parameters import set_parameters, params2dict
from scipy.optimize import fsolve

class Viscosity_getter:
    def __init__(self, folder, a, power):
        self.s = pickle.load(open(folder + 'visc_' + str(float(a)) + '_' + str(float(power)) + '_backup.pckl', 'rb'))
        
    def predict(self, gamma):
        return self.s(gamma)

def get_rbc_params(udx, gamma_in, eta_in, rho):
    prms = udx.Interactions.MembraneParameters()
    set_parameters(prms, gamma_in, eta_in, rho)

    return prms


#====================================================================================
#====================================================================================   

parser = argparse.ArgumentParser(description='Run the simulation')

parser.add_argument('--debug-lvl', help='Debug level', type=int, default=3)
parser.add_argument('--resource-folder', help='Path to all the required files', type=str, default='./')
parser.add_argument('--niters', help='Number of steps to run', type=int, default=50000)

parser.add_argument('--rho', help='Particle density', type=float, default=8)
parser.add_argument('--a', help='a', default=80, type=float)
parser.add_argument('--gamma', help='gamma', default=20, type=float)
parser.add_argument('--kbt', help='kbt', default=0.5, type=float)
parser.add_argument('--dt', help='Time step', default=0.0005, type=float)
parser.add_argument('--power', help='Kernel exponent', default=0.5, type=float)

parser.add_argument('--domain', help='Domain size', type=float, nargs=3, default=[64,64,64])
parser.add_argument('--nranks', help='MPI ranks',   type=int,   nargs=3, default=[1,1,1])

parser.add_argument('--with-dumps', help='Enable data-dumps', action='store_true')

parser.add_argument('--dry-run', help="Don't run the simulation, just report the parameters", action='store_true')

args, unknown = parser.parse_known_args()

#====================================================================================
#====================================================================================

visc_getter = Viscosity_getter(args.resource_folder, args.a, args.power)
mu = visc_getter.predict(args.gamma)

# RBC parameters
rbc_params = get_rbc_params(udx, args.gamma, mu, args.rho)

#====================================================================================
#====================================================================================

def report():
    print('Started with the following parameters: ' + str(args))
    if unknown is not None and len(unknown) > 0:
        print('Some arguments are not recognized and will be ignored: ' + str(unknown))
    print('Cell parameters: %s' % str(params2dict(rbc_params)))
    print('')
    sys.stdout.flush()


if args.dry_run:
    report()
    quit()

u = udx.udevicex(tuple(args.nranks), tuple(args.domain), debug_level=args.debug_lvl, log_filename='log')

if u.isMasterTask():
    report()

#====================================================================================
#====================================================================================

solvent = udx.ParticleVectors.ParticleVector('solvent', mass = 1.0)
ic = udx.InitialConditions.Uniform(density=args.rho)
u.registerParticleVector(pv=solvent, ic=ic)

# Interactions:
#   DPD
dpd = udx.Interactions.DPD('dpd', rc=1.0, a=args.a, gamma=args.gamma, kbt=args.kbt, dt=args.dt, power=args.power)
u.registerInteraction(dpd)
#   Contact (LJ)
contact = udx.Interactions.LJ('contact', rc=1.0, epsilon=1.0, sigma=0.9, object_aware=False, max_force=750)
u.registerInteraction(contact)
#   Membrane
membrane_int = udx.Interactions.MembraneForces('int_rbc', rbc_params, stressFree=False)
u.registerInteraction(membrane_int)

# Integrator
vv = udx.Integrators.VelocityVerlet('vv', dt=args.dt)
u.registerIntegrator(vv)

# RBCs
mesh_rbc = udx.ParticleVectors.MembraneMesh(args.resource_folder + 'rbc_mesh.off')
rbcs = udx.ParticleVectors.MembraneVector('rbc', mass=1.0, mesh=mesh_rbc)
u.registerParticleVector(pv=rbcs, ic=udx.InitialConditions.Restart('generated/'))


# Stitching things with each other
#   dpd
if u.isComputeTask():
    dpd.setSpecificPair(rbcs,    solvent,  a=0, gamma=args.gamma)
    dpd.setSpecificPair(solvent, solvent,  gamma=args.gamma)

u.setInteraction(dpd, solvent,  solvent)
u.setInteraction(dpd, rbcs,     solvent)

#   contact
u.setInteraction(contact, rbcs, rbcs)

#   membrane
u.setInteraction(membrane_int, rbcs, rbcs)
    
# Integration
u.setIntegrator(vv, solvent)
u.setIntegrator(vv, rbcs)

#====================================================================================
#====================================================================================

statsEvery=20
u.registerPlugins(udx.Plugins.createStats('stats', "stats.txt", statsEvery))

if args.with_dumps:
    sample_every = 5
    dump_every   = 1000
    bin_size     = (1., 1., 1.)

    field = udx.Plugins.createDumpAverage('field', [solvent], sample_every, dump_every, bin_size, [("velocity", "vector_from_float8")], 'h5/solvent-')
    u.registerPlugins(field)
    
    u.registerPlugins(udx.Plugins.createDumpMesh('mesh', ov=rbcs, dump_every=dump_every, path='ply/'))

u.run(args.niters)
