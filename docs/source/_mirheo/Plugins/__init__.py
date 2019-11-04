class PostprocessPlugin:
    r"""
        Base postprocess plugin class
    
    """
class SimulationPlugin:
    r"""
        Base simulation plugin class
    
    """
class AddForce(SimulationPlugin):
    r"""
        This plugin will add constant force :math:`\mathbf{F}_{extra}` to each particle of a specific PV every time-step.
        Is is advised to only use it with rigid objects, since Velocity-Verlet integrator with constant pressure can do the same without any performance penalty.
    
    """
class AddTorque(SimulationPlugin):
    r"""
        This plugin will add constant torque :math:`\mathbf{T}_{extra}` to each *object* of a specific OV every time-step.
    
    """
class AnchorParticles(SimulationPlugin):
    r"""
        This plugin will set a given particle at a given position and velocity.
    
    """
class AnchorParticlesStats(PostprocessPlugin):
    r"""
        Postprocessing side of :any:`AnchorParticles` responsible to dump the data.
    
    """
class Average3D(SimulationPlugin):
    r"""
        This plugin will project certain quantities of the particle vectors on the grid (by simple binning),
        perform time-averaging of the grid and dump it in XDMF (LINK) format with HDF5 (LINK) backend.
        The quantities of interest are represented as *channels* associated with particles vectors.
        Some interactions, integrators, etc. and more notable plug-ins can add to the Particle Vectors per-particles arrays to hold different values.
        These arrays are called *channels*.
        Any such channel may be used in this plug-in, however, user must explicitely specify the type of values that the channel holds.
        Particle number density is used to correctly average the values, so it will be sampled and written in any case.
        
        .. note::
            This plugin is inactive if postprocess is disabled
    
    """
class AverageRelative3D(SimulationPlugin):
    r"""
        This plugin acts just like the regular flow dumper, with one difference.
        It will assume a coordinate system attached to the center of mass of a specific object.
        In other words, velocities and coordinates sampled correspond to the object reference frame.
        
        .. note::
            Note that this plugin needs to allocate memory for the grid in the full domain, not only in the corresponding MPI subdomain.
            Therefore large domains will lead to running out of memory
            
        .. note::
            This plugin is inactive if postprocess is disabled
    
    """
class DensityControlPlugin(SimulationPlugin):
    r"""
        This plugin applies forces to a set of particle vectors in order to get a constant density.
    
    """
class DensityOutletPlugin(SimulationPlugin):
    r"""
        This plugin removes particles from a set of :any:`ParticleVector` in a given region if the number density is larger than a given target.
    
    """
class ExchangePVSFluxPlane(SimulationPlugin):
    r"""
        This plugin exchanges particles from a particle vector crossing a given plane to another particle vector.
        A particle with position x, y, z has crossed the plane if ax + by + cz + d >= 0, where a, b, c and d are the coefficient 
        stored in the 'plane' variable
    
    """
class ForceSaver(SimulationPlugin):
    r"""
        This plugin creates an extra channel per particle inside the given particle vector named 'forces'.
        It copies the total forces at each time step and make it accessible by other plugins.
        The forces are stored in an array of real3.
    
    """
class ImposeProfile(SimulationPlugin):
    r"""
        This plugin will set the velocity of each particle inside a given domain to a target velocity with an additive term 
        drawn from Maxwell distribution of the given temperature. 
    
    """
class ImposeVelocity(SimulationPlugin):
    r"""
        This plugin will add velocity to all the particles of the target PV in the specified area (rectangle) such that the average velocity equals to desired.
        
    """
    def set_target_velocity():
        r"""set_target_velocity(arg0: real3) -> None

        """
        pass

class MagneticOrientation(SimulationPlugin):
    r"""
        This plugin gives a magnetic moment :math:`\mathbf{M}` to every rigid objects in a given :any:`RigidObjectVector`.
        It also models a uniform magnetic field :math:`\mathbf{B}` (varying in time) and adds the induced torque to the objects according to:

        .. math::

            \mathbf{T} = \mathbf{M} \times \mathbf{B}   

        The magnetic field is passed as a function from python.
        The function must take a real (time) as input and output a tuple of three reals (magnetic field).
    
    """
class MembraneExtraForce(SimulationPlugin):
    r"""
        This plugin adds a given external force to a given membrane. 
        The force is defined vertex wise and does not depend on position.
        It is the same for all membranes belonging to the same particle vector.
    
    """
class MeshDumper(PostprocessPlugin):
    r"""
        Postprocess side plugin of :any:`MeshPlugin`.
        Responsible for performing the data reductions and I/O.
    
    """
class MeshPlugin(SimulationPlugin):
    r"""
        This plugin will write the meshes of all the object of the specified Object Vector in a PLY format (LINK).
   
        .. note::
            This plugin is inactive if postprocess is disabled
    
    """
class ObjStats(SimulationPlugin):
    r"""
        This plugin will write the coordinates of the centers of mass of the objects of the specified Object Vector.
        Instantaneous quantities (COM velocity, angular velocity, force, torque) are also written.
        If the objects are rigid bodies, also will be written the quaternion describing the rotation.
        The `type id` field is also dumped if the objects have this field activated (see :class:`~InitialConditions.MembraneWithTypeId`).
        
        The file format is the following:
        
        <object id> <simulation time> <COM>x3 [<quaternion>x4] <velocity>x3 <angular velocity>x3 <force>x3 <torque>x3 [<type id>]
        
        .. note::
            Note that all the written values are *instantaneous*
            
        .. note::
            This plugin is inactive if postprocess is disabled
    
    """
class ObjStatsDumper(PostprocessPlugin):
    r"""
        Postprocess side plugin of :any:`ObjStats`.
        Responsible for performing the I/O.
    
    """
class ObjectPortalDestination(SimulationPlugin):
    r"""
        This plugin receives object vector content from another Mirheo instance.
        Currently works only for single rank simulations.
    
    """
class ObjectPortalSource(SimulationPlugin):
    r"""
        This plugin sends object vector content to another Mirheo instance.
        Currently works only for single rank simulations.

        Sends to destination all objects that touch the portal box. The
        destination tracks portal-assigned IDs to differentiate between objects
        that have already arrived and that are new to the destination side. To
        treat objects as new when they cross the periodic boundary, a marker
        plane must be given. Objects are considered then new as soon as their
        center of mass crosses the plane.
    
    """
class ObjectToParticlesPlugin(SimulationPlugin):
    r"""
        This plugin transforms objects to particles when they cross a given plane.
    
    """
class ParticleChannelSaver(SimulationPlugin):
    r"""
        This plugin creates an extra channel per particle inside the given particle vector with a given name.
        It copies the content of an extra channel of pv at each time step and make it accessible by other plugins.
    
    """
class ParticleChecker(SimulationPlugin):
    r"""
        This plugin will check the positions and velocities of all particles in the simulation every given time steps.
        To be used for debugging purpose.
    
    """
class ParticleDisplacementPlugin(SimulationPlugin):
    r"""
        This plugin computes and save the displacement of the particles within a given particle vector.
        The result is stored inside the extra channel "displacements" as an array of real3.
    
    """
class ParticleDrag(SimulationPlugin):
    r"""
        This plugin will add drag force :math:`\mathbf{f} = - C_d \mathbf{u}` to each particle of a specific PV every time-step.
    
    """
class ParticleDumperPlugin(PostprocessPlugin):
    r"""
        Postprocess side plugin of :any:`ParticleSenderPlugin`.
        Responsible for performing the I/O.
    
    """
class ParticlePortalDestination(SimulationPlugin):
    r"""
        This plugin receives particle vector content from another Mirheo instance.
        Currently works only for single rank simulations.
    
    """
class ParticlePortalSource(SimulationPlugin):
    r"""
        This plugin sends particle vector content to another Mirheo instance.
        Currently works only for single rank simulations.
    
    """
class ParticleSenderPlugin(SimulationPlugin):
    r"""
        This plugin will dump positions, velocities and optional attached data of all the particles of the specified Particle Vector.
        The data is dumped into hdf5 format. An additional xdfm file is dumped to describe the data and make it readable by visualization tools. 
    
    """
class ParticleSenderWithRodDataPlugin(SimulationPlugin):
    r"""
        Extension of :any:`ParticleSenderPlugin` to support bisegment data.
        If a field of optional data is per bisegment data (for a rod) this plugin will first scatter this data to particles.
    
    """
class ParticleWithMeshDumperPlugin(PostprocessPlugin):
    r"""
        Postprocess side plugin of :any:`ParticleWithMeshSenderPlugin`.
        Responsible for performing the I/O.
    
    """
class ParticleWithMeshSenderPlugin(SimulationPlugin):
    r"""
        This plugin will dump positions, velocities and optional attached data of all the particles of the specified Object Vector, as well as connectivity information.
        The data is dumped into hdf5 format. An additional xdfm file is dumped to describe the data and make it readable by visualization tools. 
    
    """
class PinObject(SimulationPlugin):
    r"""
        This plugin will impose given velocity as the center of mass velocity (by axis) of all the objects of the specified Object Vector.
        If the objects are rigid bodies, rotatation may be restricted with this plugin as well.
        The *time-averaged* force and/or torque required to impose the velocities and rotations are reported.
            
        .. note::
            This plugin is inactive if postprocess is disabled
    
    """
class PinRodExtremity(SimulationPlugin):
    r"""
        This plugin adds a force on a given segment of all the rods in a :any:`RodVector`.
        The force has the form deriving from the potential

        .. math::
            
            E = k \left( 1 - \cos \theta \right),

        where :math:`\theta` is the angle between the material frame and a given direction (projected on the concerned segment).
        Note that the force is applied only on the material frame and not on the center line.
    
    """
class PlaneOutletPlugin(SimulationPlugin):
    r"""
        This plugin removes all particles from a set of :any:`ParticleVector` that are on the non-negative side of a given plane.
    
    """
class PostprocessDensityControl(PostprocessPlugin):
    r"""
        Dumps info from :any:`DensityControlPlugin`.
    
    """
class PostprocessRadialVelocityControl(PostprocessPlugin):
    r"""
        Postprocess side plugin of :any:`RadialVelocityControl`.
        Responsible for performing the I/O.
    
    """
class PostprocessStats(PostprocessPlugin):
    r"""
        Postprocess side plugin of :any:`SimulationStats`.
        Responsible for performing the data reductions and I/O.
    
    """
class PostprocessVelocityControl(PostprocessPlugin):
    r"""
        Postprocess side plugin of :any:`VelocityControl`.
        Responsible for performing the I/O.
    
    """
class RadialVelocityControl(SimulationPlugin):
    r"""
        This plugin applies a radial force (decreasing as :math:`r^3`) to all the particles of the target PVS.
        The force is adapted via a PID controller such that the average of the velocity times radial position of the particles matches a target value.
    
    """
class RateOutletPlugin(SimulationPlugin):
    r"""
        This plugin removes particles from a set of :any:`ParticleVector` in a given region at a given mass rate.
    
    """
class ReportPinObject(PostprocessPlugin):
    r"""
        Postprocess side plugin of :any:`PinObject`.
        Responsible for performing the I/O.
    
    """
class SimulationStats(SimulationPlugin):
    r"""
        This plugin will report aggregate quantities of all the particles in the simulation:
        total number of particles in the simulation, average temperature and momentum, maximum velocity magnutide of a particle
        and also the mean real time per step in milliseconds.
        
        .. note::
            This plugin is inactive if postprocess is disabled
    
    """
class Temperaturize(SimulationPlugin):
    r"""
        This plugin changes the velocity of each particles from a given :any:`ParticleVector`.
        It can operate under two modes: `keepVelocity = True`, in which case it adds a term drawn from a Maxwell distribution to the current velocity;
        `keepVelocity = False`, in which case it sets the velocity to a term drawn from a Maxwell distribution.
    
    """
class UniformCartesianDumper(PostprocessPlugin):
    r"""
        Postprocess side plugin of :any:`Average3D` or :any:`AverageRelative3D`.
        Responsible for performing the I/O.
    
    """
    def get_channel_view():
        r"""get_channel_view(arg0: str) -> array

        """
        pass

class VelocityControl(SimulationPlugin):
    r"""
        This plugin applies a uniform force to all the particles of the target PVS in the specified area (rectangle).
        The force is adapted bvia a PID controller such that the velocity average of the particles matches the target average velocity.
    
    """
class VelocityInlet(SimulationPlugin):
    r"""
        This plugin inserts particles in a given :any:`ParticleVector`.
        The particles are inserted on a given surface with given velocity inlet. 
        The rate of insertion is governed by the velocity and the given number density.
    
    """
class VirialPressure(SimulationPlugin):
    r"""
        This plugin compute the virial pressure from a given :any:`ParticleVector`.
        Note that the stress computation must be enabled with the corresponding stressName.
        This returns the total internal virial part only (no temperature term).
        Note that the volume is not devided in the result, the user is responsible to properly scale the output.
    
    """
class VirialPressureDumper(PostprocessPlugin):
    r"""
        Postprocess side plugin of :any:`VirialPressure`.
        Responsible for performing the I/O.
    
    """
class WallForceCollector(SimulationPlugin):
    r"""
        This plugin collects and average the total force exerted on a given wall.
        The result has 2 components:
        
            * bounce back: force necessary to the momentum change
            * frozen particles: total interaction force exerted on the frozen particles
    
    """
class WallForceDumper(PostprocessPlugin):
    r"""
        Postprocess side plugin of :any:`WallForceCollector`.
        Responsible for the I/O part.
    
    """
class WallRepulsion(SimulationPlugin):
    r"""
        This plugin will add force on all the particles that are nearby a specified wall. The motivation of this plugin is as follows.
        The particles of regular PVs are prevented from penetrating into the walls by Wall Bouncers.
        However, using Wall Bouncers with Object Vectors may be undesirable (e.g. in case of a very viscous membrane) or impossible (in case of rigid objects).
        In these cases one can use either strong repulsive potential between the object and the wall particle or alternatively this plugin.
        The advantage of the SDF-based repulsion is that small penetrations won't break the simulation.
        
        The force expression looks as follows:
        
        .. math::
        
            \mathbf{F}(\mathbf{r}) = \mathbf{\nabla}S(\mathbf{r}) \cdot \begin{cases}
                0, & S(\mathbf{r}) < -h,\\
                \min(F_\text{max}, C (S(\mathbf{r}) + h)), & S(\mathbf{r}) \geqslant -h,\\
            \end{cases}

        where :math:`S` is the SDF of the wall, :math:`C`, :math:`F_\text{max}` and :math:`h` are parameters.
    
    """
class XYZDumper(PostprocessPlugin):
    r"""
        Postprocess side plugin of :any:`XYZPlugin`.
        Responsible for the I/O part.
    
    """
class XYZPlugin(SimulationPlugin):
    r"""
        This plugin will dump positions of all the particles of the specified Particle Vector in the XYZ format.
   
        .. note::
            This plugin is inactive if postprocess is disabled
    
    """

# Functions

def createAddForce():
    r"""createAddForce(state: MirState, name: str, pv: ParticleVectors.ParticleVector, force: real3) -> Tuple[Plugins.AddForce, Plugins.PostprocessPlugin]


        Create :any:`AddForce` plugin
        
        Args:
            name: name of the plugin
            pv: :any:`ParticleVector` that we'll work with
            force: extra force
    

    """
    pass

def createAddTorque():
    r"""createAddTorque(state: MirState, name: str, ov: ParticleVectors.ParticleVector, torque: real3) -> Tuple[Plugins.AddTorque, Plugins.PostprocessPlugin]


        Create :any:`AddTorque` plugin
        
        Args:
            name: name of the plugin
            ov: :any:`ObjectVector` that we'll work with
            torque: extra torque (per object)
    

    """
    pass

def createAnchorParticles():
    r"""createAnchorParticles(state: MirState, name: str, pv: ParticleVectors.ParticleVector, positions: Callable[[float], List[real3]], velocities: Callable[[float], List[real3]], pids: List[int], report_every: int, path: str) -> Tuple[Plugins.AnchorParticles, Plugins.AnchorParticlesStats]


        Create :any:`AnchorParticles` plugin
        
        Args:
            name: name of the plugin
            pv: :any:`ParticleVector` that we'll work with
            positions: positions (at given time) of the particles
            velocities: velocities (at given time) of the particles
            pids: global ids of the particles in the given particle vector
            report_every: report the time averaged force acting on the particles every this amount of timesteps
            path: folder where to dump the stats
    

    """
    pass

def createDensityControl():
    r"""createDensityControl(state: MirState, name: str, file_name: str, pvs: List[ParticleVectors.ParticleVector], target_density: float, region: Callable[[real3], float], resolution: real3, level_lo: float, level_hi: float, level_space: float, Kp: float, Ki: float, Kd: float, tune_every: int, dump_every: int, sample_every: int) -> Tuple[Plugins.DensityControlPlugin, Plugins.PostprocessDensityControl]


        Create :any:`DensityControlPlugin`
        
        Args:
            name: name of the plugin
            file_name: output filename 
            pvs: list of :any:`ParticleVector` that we'll work with
            target_density: target number density (used only at boundaries of level sets)
            region: a scalar field which describes how to subdivide the domain. 
                    It must be continuous and differentiable, as the forces are in the gradient direction of this field
            resolution: grid resolution to represent the region field
            level_lo: lower level set to apply the controller on
            level_hi: highest level set to apply the controller on
            level_space: the size of one subregion in terms of level sets
            Kp, Ki, Kd: pid control parameters
            tune_every: update the forces every this amount of time steps
            dump_every: dump densities and forces in file ``filename``
            sample_every: sample to average densities every this amount of time steps
    

    """
    pass

def createDensityOutlet():
    r"""createDensityOutlet(state: MirState, name: str, pvs: List[ParticleVectors.ParticleVector], number_density: float, region: Callable[[real3], float], resolution: real3) -> Tuple[Plugins.DensityOutletPlugin, Plugins.PostprocessPlugin]


        Create :any:`DensityOutletPlugin`
        
        Args:
            name: name of the plugin
            pvs: list of :any:`ParticleVector` that we'll work with
            number_density: maximum number_density in the region
            region: a function that is negative in the concerned region and positive outside
            resolution: grid resolution to represent the region field
        
    

    """
    pass

def createDumpAverage():
    r"""createDumpAverage(state: MirState, name: str, pvs: List[ParticleVectors.ParticleVector], sample_every: int, dump_every: int, bin_size: real3 = real3(1.0, 1.0, 1.0), channels: List[Tuple[str, str]], path: str = 'xdmf/') -> Tuple[Plugins.Average3D, Plugins.UniformCartesianDumper]


        Create :any:`Average3D` plugin
        
        Args:
            name: name of the plugin
            pvs: list of :any:`ParticleVector` that we'll work with
            sample_every: sample quantities every this many time-steps
            dump_every: write files every this many time-steps 
            bin_size: bin size for sampling. The resulting quantities will be *cell-centered*
            path: Path and filename prefix for the dumps. For every dump two files will be created: <path>_NNNNN.xmf and <path>_NNNNN.h5
            channels: list of pairs name - type.
                Name is the channel (per particle) name. Always available channels are:
                    
                * 'velocity' with type "real4"
                
                Type is to provide the type of quantity to extract from the channel.                                            
                Type can also define a simple transformation from the channel internal structure                 
                to the datatype supported in HDF5 (i.e. scalar, vector, tensor)                                  
                Available types are:                                                                             
                                                                                                                
                * 'scalar': 1 real per particle
                * 'vector': 3 reals per particle
                * 'vector_from_float4': 4 reals per particle. 3 first reals will form the resulting vector
                * 'tensor6': 6 reals per particle, symmetric tensor in order xx, xy, xz, yy, yz, zz
                
    

    """
    pass

def createDumpAverageRelative():
    r"""createDumpAverageRelative(state: MirState, name: str, pvs: List[ParticleVectors.ParticleVector], relative_to_ov: ParticleVectors.ObjectVector, relative_to_id: int, sample_every: int, dump_every: int, bin_size: real3 = real3(1.0, 1.0, 1.0), channels: List[Tuple[str, str]], path: str = 'xdmf/') -> Tuple[Plugins.AverageRelative3D, Plugins.UniformCartesianDumper]


              
        Create :any:`AverageRelative3D` plugin
                
        The arguments are the same as for createDumpAverage() with a few additions
        
        Args:
            relative_to_ov: take an object governing the frame of reference from this :any:`ObjectVector`
            relative_to_id: take an object governing the frame of reference with the specific ID
    

    """
    pass

def createDumpMesh():
    r"""createDumpMesh(state: MirState, name: str, ov: ParticleVectors.ObjectVector, dump_every: int, path: str) -> Tuple[Plugins.MeshPlugin, Plugins.MeshDumper]


        Create :any:`MeshPlugin` plugin
        
        Args:
            name: name of the plugin
            ov: :any:`ObjectVector` that we'll work with
            dump_every: write files every this many time-steps
            path: the files will look like this: <path>/<ov_name>_NNNNN.ply
    

    """
    pass

def createDumpObjectStats():
    r"""createDumpObjectStats(state: MirState, name: str, ov: ParticleVectors.ObjectVector, dump_every: int, path: str) -> Tuple[Plugins.ObjStats, Plugins.ObjStatsDumper]


        Create :any:`ObjStats` plugin
        
        Args:
            name: name of the plugin
            ov: :any:`ObjectVector` that we'll work with
            dump_every: write files every this many time-steps
            path: the files will look like this: <path>/<ov_name>_NNNNN.txt
    

    """
    pass

def createDumpParticles():
    r"""createDumpParticles(state: MirState, name: str, pv: ParticleVectors.ParticleVector, dump_every: int, channels: List[Tuple[str, str]], path: str) -> Tuple[Plugins.ParticleSenderPlugin, Plugins.ParticleDumperPlugin]


        Create :any:`ParticleSenderPlugin` plugin
        
        Args:
            name: name of the plugin
            pv: :any:`ParticleVector` that we'll work with
            dump_every: write files every this many time-steps 
            path: Path and filename prefix for the dumps. For every dump two files will be created: <path>_NNNNN.xmf and <path>_NNNNN.h5
            channels: list of pairs name - type.
                Name is the channel (per particle) name.
                The "velocity" and "id" channels are always activated.
                Type is to provide the type of quantity to extract from the channel.                                            
                Available types are:                                                                             
                                                                                                                
                * 'scalar': 1 real per particle
                * 'vector': 3 reals per particle
                * 'tensor6': 6 reals per particle, symmetric tensor in order xx, xy, xz, yy, yz, zz
                
    

    """
    pass

def createDumpParticlesWithMesh():
    r"""createDumpParticlesWithMesh(state: MirState, name: str, ov: ParticleVectors.ObjectVector, dump_every: int, channels: List[Tuple[str, str]], path: str) -> Tuple[Plugins.ParticleWithMeshSenderPlugin, Plugins.ParticleWithMeshDumperPlugin]


        Create :any:`ParticleWithMeshSenderPlugin` plugin
        
        Args:
            name: name of the plugin
            ov: :any:`ObjectVector` that we'll work with
            dump_every: write files every this many time-steps 
            path: Path and filename prefix for the dumps. For every dump two files will be created: <path>_NNNNN.xmf and <path>_NNNNN.h5
            channels: list of pairs name - type.
                Name is the channel (per particle) name.
                The "velocity" and "id" channels are always activated.
                Type is to provide the type of quantity to extract from the channel.                                            
                Available types are:                                                                             
                                                                                                                
                * 'scalar': 1 real per particle
                * 'vector': 3 reals per particle
                * 'tensor6': 6 reals per particle, symmetric tensor in order xx, xy, xz, yy, yz, zz
                
    

    """
    pass

def createDumpParticlesWithRodData():
    r"""createDumpParticlesWithRodData(state: MirState, name: str, rv: ParticleVectors.ParticleVector, dump_every: int, channels: List[Tuple[str, str]], path: str) -> Tuple[Plugins.ParticleSenderWithRodDataPlugin, Plugins.ParticleDumperPlugin]


        Create :any:`ParticleSenderWithRodDataPlugin` plugin
        The interface is the same as :any:`createDumpParticles`

        Args:
            name: name of the plugin
            rv: :any:`RodVector` that we'll work with
            dump_every: write files every this many time-steps 
            path: Path and filename prefix for the dumps. For every dump two files will be created: <path>_NNNNN.xmf and <path>_NNNNN.h5
            channels: list of pairs name - type.
                Name is the channel (per particle) name.
                The "velocity" and "id" channels are always activated.
                Type is to provide the type of quantity to extract from the channel.                                            
                Available types are:

                * 'scalar': 1 real per particle
                * 'vector': 3 reals per particle
                * 'tensor6': 6 reals per particle, symmetric tensor in order xx, xy, xz, yy, yz, zz
    

    """
    pass

def createDumpXYZ():
    r"""createDumpXYZ(state: MirState, name: str, pv: ParticleVectors.ParticleVector, dump_every: int, path: str) -> Tuple[Plugins.XYZPlugin, Plugins.XYZDumper]


        Create :any:`XYZPlugin` plugin
        
        Args:
            name: name of the plugin
            pvs: list of :any:`ParticleVector` that we'll work with
            dump_every: write files every this many time-steps
            path: the files will look like this: <path>/<pv_name>_NNNNN.xyz
    

    """
    pass

def createExchangePVSFluxPlane():
    r"""createExchangePVSFluxPlane(state: MirState, name: str, pv1: ParticleVectors.ParticleVector, pv2: ParticleVectors.ParticleVector, plane: real4) -> Tuple[Plugins.ExchangePVSFluxPlane, Plugins.PostprocessPlugin]


        Create :any:`ExchangePVSFluxPlane` plugin
        
        Args:
            name: name of the plugin
            pv1: :class:`ParticleVector` source
            pv2: :class:`ParticleVector` destination
            plane: 4 coefficients for the plane equation ax + by + cz + d >= 0
    

    """
    pass

def createForceSaver():
    r"""createForceSaver(state: MirState, name: str, pv: ParticleVectors.ParticleVector) -> Tuple[Plugins.ForceSaver, Plugins.PostprocessPlugin]


        Create :any:`ForceSaver` plugin
        
        Args:
            name: name of the plugin
            pv: :any:`ParticleVector` that we'll work with
    

    """
    pass

def createImposeProfile():
    r"""createImposeProfile(state: MirState, name: str, pv: ParticleVectors.ParticleVector, low: real3, high: real3, velocity: real3, kBT: float) -> Tuple[Plugins.ImposeProfile, Plugins.PostprocessPlugin]


        Create :any:`ImposeProfile` plugin
        
        Args:
            name: name of the plugin
            pv: :any:`ParticleVector` that we'll work with
            low: the lower corner of the domain
            high: the higher corner of the domain
            velocity: target velocity
            kBT: temperature in the domain (appropriate Maxwell distribution will be used)
    

    """
    pass

def createImposeVelocity():
    r"""createImposeVelocity(state: MirState, name: str, pvs: List[ParticleVectors.ParticleVector], every: int, low: real3, high: real3, velocity: real3) -> Tuple[Plugins.ImposeVelocity, Plugins.PostprocessPlugin]


        Create :any:`ImposeVelocity` plugin
        
        Args:
            name: name of the plugin
            pvs: list of :any:`ParticleVector` that we'll work with
            every: change the velocities once in **every** timestep
            low: the lower corner of the domain
            high: the higher corner of the domain
            velocity: target velocity
    

    """
    pass

def createMagneticOrientation():
    r"""createMagneticOrientation(state: MirState, name: str, rov: ParticleVectors.RigidObjectVector, moment: real3, magneticFunction: Callable[[float], real3]) -> Tuple[Plugins.MagneticOrientation, Plugins.PostprocessPlugin]


        Create :any:`MagneticOrientation` plugin
        
        Args:
            name: name of the plugin
            rov: :class:`RigidObjectVector` with which the magnetic field will interact
            moment: magnetic moment per object
            magneticFunction: a function that depends on time and returns a uniform (real3) magnetic field
    

    """
    pass

def createMembraneExtraForce():
    r"""createMembraneExtraForce(state: MirState, name: str, pv: ParticleVectors.ParticleVector, forces: List[real3]) -> Tuple[Plugins.MembraneExtraForce, Plugins.PostprocessPlugin]


        Create :any:`MembraneExtraForce` plugin
        
        Args:
            name: name of the plugin
            pv: :class:`ParticleVector` to which the force should be added
            forces: array of forces, one force (3 reals) per vertex in a single mesh
    

    """
    pass

def createObjectPortalDestination():
    r"""createObjectPortalDestination(state: MirState, name: str, ov: ParticleVectors.ObjectVector, src: real3, dst: real3, size: real3, tag: int, interCommPtr: int) -> Tuple[Plugins.ObjectPortalDestination, Plugins.PostprocessPlugin]


        Create :any:`ObjectPortalDestination` plugin

        Args:
            name: name of the plugin
            ov: target object vector
            src: lower corner of the portal on the source side
            dst: lower corner of the portal on the destination side
            size: portal size
            tag: tag to use for MPI communication
            interCommPtr: pointer to a MPI_Comm intercommunicator between Mirheo instances.
    

    """
    pass

def createObjectPortalSource():
    r"""createObjectPortalSource(state: MirState, name: str, ov: ParticleVectors.ObjectVector, src: real3, dst: real3, size: real3, plane: real4, tag: int, interCommPtr: int) -> Tuple[Plugins.ObjectPortalSource, Plugins.PostprocessPlugin]


        Create :any:`ObjectPortalSource` plugin

        Args:
            name: name of the plugin
            ov: source object vector
            src: lower corner of the portal on the source side
            dst: lower corner of the portal on the destination side
            size: portal size
            plane: plane after which the objects get a new unique identifier
                Should be far from the source portal and slightly away of the domain boundary.
            tag: tag to use for MPI communication
            interCommPtr: pointer to a MPI_Comm intercommunicator between Mirheo instances.
    

    """
    pass

def createObjectToParticlesPlugin():
    r"""createObjectToParticlesPlugin(state: MirState, name: str, ov: ParticleVectors.ObjectVector, pv: ParticleVectors.ParticleVector, plane: real4) -> Tuple[Plugins.ObjectToParticlesPlugin, Plugins.PostprocessPlugin]


        Create :any:`ObjectPortalSource` plugin

        Args:
            name: name of the plugin
            ov: source object vector
            pv: target particle vector
            plane: plane `(a, b, c, d)` defined as `a*x + b*y + c*z + d == 0`
    

    """
    pass

def createParticleChannelSaver():
    r"""createParticleChannelSaver(state: MirState, name: str, pv: ParticleVectors.ParticleVector, channelName: str, savedName: str) -> Tuple[Plugins.ParticleChannelSaver, Plugins.PostprocessPlugin]


        Create :any:`ParticleChannelSaver` plugin
        
        Args:
            name: name of the plugin
            pv: :any:`ParticleVector` that we'll work with
            channelName: the name of the source channel
            savedName: name of the extra channel
    

    """
    pass

def createParticleChecker():
    r"""createParticleChecker(state: MirState, name: str, check_every: int) -> Tuple[Plugins.ParticleChecker, Plugins.PostprocessPlugin]


        Create :any:`ParticleChecker` plugin
        
        Args:
            name: name of the plugin
            check_every: check every this amount of time steps
    

    """
    pass

def createParticleDisplacement():
    r"""createParticleDisplacement(state: MirState, name: str, pv: ParticleVectors.ParticleVector, update_every: int) -> Tuple[Plugins.ParticleDisplacementPlugin, Plugins.PostprocessPlugin]


        Create :any:`ParticleDisplacementPlugin`
        
        Args:
            name: name of the plugin
            pv: :any:`ParticleVector` that we'll work with
            update_every: displacements are computed between positions separated by this amount of timesteps
    

    """
    pass

def createParticleDrag():
    r"""createParticleDrag(state: MirState, name: str, pv: ParticleVectors.ParticleVector, drag: float) -> Tuple[Plugins.ParticleDrag, Plugins.PostprocessPlugin]


        Create :any:`ParticleDrag` plugin
        
        Args:
            name: name of the plugin
            pv: :any:`ParticleVector` that we'll work with
            drag: drag coefficient
    

    """
    pass

def createParticlePortalDestination():
    r"""createParticlePortalDestination(state: MirState, name: str, ov: ParticleVectors.ParticleVector, src: real3, dst: real3, size: real3, tag: int, interCommPtr: int) -> Tuple[Plugins.ParticlePortalDestination, Plugins.PostprocessPlugin]


        Create :any:`ParticlePortalDestination` plugin

        Args:
            name: name of the plugin
            ...
            ...
            ..
    

    """
    pass

def createParticlePortalSource():
    r"""createParticlePortalSource(state: MirState, name: str, ov: ParticleVectors.ParticleVector, src: real3, dst: real3, size: real3, tag: int, interCommPtr: int) -> Tuple[Plugins.ParticlePortalSource, Plugins.PostprocessPlugin]


        Create :any:`ParticlePortalSource` plugin

        Args:
            name: name of the plugin
            ...
            ...
            ..
    

    """
    pass

def createPinObject():
    r"""createPinObject(state: MirState, name: str, ov: ParticleVectors.ObjectVector, dump_every: int, path: str, velocity: real3, angular_velocity: real3) -> Tuple[Plugins.PinObject, Plugins.ReportPinObject]


        Create :any:`PinObject` plugin
        
        Args:
            name: name of the plugin
            ov: :any:`ObjectVector` that we'll work with
            dump_every: write files every this many time-steps
            path: the files will look like this: <path>/<ov_name>_NNNNN.txt
            velocity: 3 reals, each component is the desired object velocity.
                If the corresponding component should not be restricted, set this value to :python:`PinObject::Unrestricted`
            angular_velocity: 3 reals, each component is the desired object angular velocity.
                If the corresponding component should not be restricted, set this value to :python:`PinObject::Unrestricted`
    

    """
    pass

def createPinRodExtremity():
    r"""createPinRodExtremity(state: MirState, name: str, rv: ParticleVectors.RodVector, segment_id: int, f_magn: float, target_direction: real3) -> Tuple[Plugins.PinRodExtremity, Plugins.PostprocessPlugin]


        Create :any:`PinRodExtremity` plugin
        
        Args:
            name: name of the plugin
            rv: :any:`RodVector` that we'll work with
            segment_id: the segment to which the plugin is active
            f_magn: force magnitude
            target_direction: the direction in which the material frame tends to align
    

    """
    pass

def createPlaneOutlet():
    r"""createPlaneOutlet(state: MirState, name: str, pvs: List[ParticleVectors.ParticleVector], plane: real4) -> Tuple[Plugins.PlaneOutletPlugin, Plugins.PostprocessPlugin]


        Create :any:`PlaneOutletPlugin`

        Args:
            name: name of the plugin
            pvs: list of :any:`ParticleVector` that we'll work with
            plane: Tuple (a, b, c, d). Particles are removed if `ax + by + cz + d >= 0`.
    

    """
    pass

def createRadialVelocityControl():
    r"""createRadialVelocityControl(state: MirState, name: str, filename: str, pvs: List[ParticleVectors.ParticleVector], minRadius: float, maxRadius: float, sample_every: int, tune_every: int, dump_every: int, center: real3, target_vel: float, Kp: float, Ki: float, Kd: float) -> Tuple[Plugins.RadialVelocityControl, Plugins.PostprocessRadialVelocityControl]


        Create :any:`VelocityControl` plugin
        
        Args:
            name: name of the plugin
            filename: dump file name 
            pvs: list of concerned :class:`ParticleVector`
            minRadius, maxRadius: only particles within this distance are considered 
            sample_every: sample velocity every this many time-steps
            tune_every: adapt the force every this many time-steps
            dump_every: write files every this many time-steps
            center: center of the radial coordinates
            target_vel: the target mean velocity of the particles at :math:`r=1`
            Kp, Ki, Kd: PID controller coefficients
    

    """
    pass

def createRateOutlet():
    r"""createRateOutlet(state: MirState, name: str, pvs: List[ParticleVectors.ParticleVector], mass_rate: float, region: Callable[[real3], float], resolution: real3) -> Tuple[Plugins.RateOutletPlugin, Plugins.PostprocessPlugin]


        Create :any:`RateOutletPlugin`
        
        Args:
            name: name of the plugin
            pvs: list of :any:`ParticleVector` that we'll work with
            mass_rate: total outlet mass rate in the region
            region: a function that is negative in the concerned region and positive outside
            resolution: grid resolution to represent the region field
        
    

    """
    pass

def createStats():
    r"""createStats(state: MirState, name: str, filename: str = '', every: int) -> Tuple[Plugins.SimulationStats, Plugins.PostprocessStats]


        Create :any:`SimulationStats` plugin
        
        Args:
            name: name of the plugin
            filename: the stats will also be recorded to that file in a computer-friendly way
            every: report to standard output every that many time-steps
    

    """
    pass

def createTemperaturize():
    r"""createTemperaturize(state: MirState, name: str, pv: ParticleVectors.ParticleVector, kBT: float, keepVelocity: bool) -> Tuple[Plugins.Temperaturize, Plugins.PostprocessPlugin]


        Create :any:`Temperaturize` plugin

        Args:
            name: name of the plugin
            pv: the concerned :any:`ParticleVector`
            kBT: the target temperature
            keepVelocity: True for adding Maxwell distribution to the previous velocity; False to set the velocity to a Maxwell distribution.
    

    """
    pass

def createVelocityControl():
    r"""createVelocityControl(state: MirState, name: str, filename: str, pvs: List[ParticleVectors.ParticleVector], low: real3, high: real3, sample_every: int, tune_every: int, dump_every: int, target_vel: real3, Kp: float, Ki: float, Kd: float) -> Tuple[Plugins.VelocityControl, Plugins.PostprocessVelocityControl]


        Create :any:`VelocityControl` plugin
        
        Args:
            name: name of the plugin
            filename: dump file name 
            pvs: list of concerned :class:`ParticleVector`
            low, high: boundaries of the domain of interest
            sample_every: sample velocity every this many time-steps
            tune_every: adapt the force every this many time-steps
            dump_every: write files every this many time-steps
            target_vel: the target mean velocity of the particles in the domain of interest
            Kp, Ki, Kd: PID controller coefficients
    

    """
    pass

def createVelocityInlet():
    r"""createVelocityInlet(state: MirState, name: str, pv: ParticleVectors.ParticleVector, implicit_surface_func: Callable[[real3], float], velocity_field: Callable[[real3], real3], resolution: real3, number_density: float, kBT: float) -> Tuple[Plugins.VelocityInlet, Plugins.PostprocessPlugin]


        Create :any:`VelocityInlet` plugin
        
        Args:
            name: name of the plugin
            pv: the :any:`ParticleVector` that we ll work with 
            implicit_surface_func: a scalar field function that has the required surface as zero level set
            velocity_field: vector field that describes the velocity on the inlet (will be evaluated on the surface only)
            resolution: grid size used to discretize the surface
            number_density: number density of the inserted solvent
            kBT: temperature of the inserted solvent
    

    """
    pass

def createVirialPressurePlugin():
    r"""createVirialPressurePlugin(state: MirState, name: str, pv: ParticleVectors.ParticleVector, regionFunc: Callable[[real3], float], h: real3, dump_every: int, path: str) -> Tuple[Plugins.VirialPressure, Plugins.VirialPressureDumper]


        Create :any:`VirialPressure` plugin
        
        Args:
            name: name of the plugin
            pv: concerned :class:`ParticleVector`
            regionFunc: predicate for the concerned region; positive inside the region and negative outside
            h: grid size for representing the predicate onto a grid
            dump_every: report total pressure every this many time-steps
            path: the folder name in which the file will be dumped
    

    """
    pass

def createWallForceCollector():
    r"""createWallForceCollector(state: MirState, name: str, wall: Walls.Wall, pvFrozen: ParticleVectors.ParticleVector, sample_every: int, dump_every: int, filename: str) -> Tuple[Plugins.WallForceCollector, Plugins.WallForceDumper]


        Create :any:`WallForceCollector` plugin
        
        Args:
            name: name of the plugin            
            wall: :any:`Wall` that we ll work with
            pvFrozen: corresponding frozen :any:`ParticleVector`
            sample_every: sample every this number of time steps
            dump_every: dump every this amount of timesteps
            filename: output filename
    

    """
    pass

def createWallRepulsion():
    r"""createWallRepulsion(state: MirState, name: str, pv: ParticleVectors.ParticleVector, wall: Walls.Wall, C: float, h: float, max_force: float) -> Tuple[Plugins.WallRepulsion, Plugins.PostprocessPlugin]


        Create :any:`WallRepulsion` plugin
        
        Args:
            name: name of the plugin
            pv: :any:`ParticleVector` that we'll work with
            wall: :any:`Wall` that defines the repulsion
            C: :math:`C`  
            h: :math:`h`  
            max_force: :math:`F_{max}`  
    

    """
    pass


