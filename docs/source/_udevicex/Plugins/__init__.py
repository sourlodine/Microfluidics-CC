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
class Average3D(SimulationPlugin):
    r"""
        This plugin will project certain quantities of the particles on the grid (by simple binning),
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
class ImposeProfile(SimulationPlugin):
    r"""
        TODO
    
    """
class ImposeVelocity(SimulationPlugin):
    r"""
        This plugin will add velocity to all the particles of the target PV in the specified area (rectangle) such that the average velocity equals to desired.
    
    """
class MeshDumper(PostprocessPlugin):
    r"""None
    """
class MeshPlugin(SimulationPlugin):
    r"""
        This plugin will write the meshes of all the object of the specified Object Vector in a PLY format (LINK).
   
        .. note::
            This plugin is inactive if postprocess is disabled
    
    """
class ObjPositions(SimulationPlugin):
    r"""
        This plugin will write the coordinates of the centers of mass of the objects of the specified Object Vector.
        If the objects are rigid bodies, also will be written: COM velocity, rotation, angular velocity, force, torque.
        
        The file format is the following:
        
        <object id> <simulation time> <COM>x3 [<quaternion>x4 <velocity>x3 <angular velocity>x3 <force>x3 <torque>x3]
        
        .. note::
            Note that all the written values are *instantaneous*
            
        .. note::
            This plugin is inactive if postprocess is disabled
    
    """
class ObjPositionsDumper(PostprocessPlugin):
    r"""None
    """
class PinObject(SimulationPlugin):
    r"""
        This plugin will fix center of mass positions (by axis) of all the objects of the specified Object Vector.
        If the objects are rigid bodies, rotatation may be restricted with this plugin as well.
        The *average* force or torque required to fix the positions or rotation are reported.
            
        .. note::
            This plugin is inactive if postprocess is disabled
    
    """
class PostprocessStats(PostprocessPlugin):
    r"""None
    """
class ReportPinObject(PostprocessPlugin):
    r"""None
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
        TODO
    
    """
class UniformCartesianDumper(PostprocessPlugin):
    r"""None
    """
class VelocityControl(SimulationPlugin):
    r"""
        This plugin applies a uniform force to all the particles of the target PV in the specified area (rectangle).
        The force is apdated by a PID controller such that the velocity average of the particles matches a target average velocity.
    
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
        
            \mathbf{F} = \mathbf{\nabla}_{sdf} \cdot \begin{cases}
                0, & sdf < -h\\
                \min(F_{max}, C (sdf + h)), & sdf \geqslant -h\\
            \end{cases}
    
    """
class XYZDumper(PostprocessPlugin):
    r"""None
    """
class XYZPlugin(SimulationPlugin):
    r"""
        This plugin will dump positions of all the particles of the specified Particle Vector in the XYZ format.
   
        .. note::
            This plugin is inactive if postprocess is disabled
    
    """

# Functions

def createAddForce():
    r"""createAddForce(compute_task: bool, name: str, pv: ParticleVectors.ParticleVector, force: Tuple[float, float, float]) -> Tuple[Plugins.AddForce, Plugins.PostprocessPlugin]


        Create :any:`AddForce` plugin
        
        Args:
            name: name of the plugin
            pv: :any:`ParticleVector` that we'll work with
            force: extra force
    

    """
    pass

def createAddTorque():
    r"""createAddTorque(compute_task: bool, name: str, ov: ParticleVectors.ParticleVector, torque: Tuple[float, float, float]) -> Tuple[Plugins.AddTorque, Plugins.PostprocessPlugin]


        Create :any:`AddTorque` plugin
        
        Args:
            name: name of the plugin
            ov: :any:`ObjectVector` that we'll work with
            torque: extra torque (per object)
    

    """
    pass

def createDumpAverage():
    r"""createDumpAverage(compute_task: bool, name: str, pv: ParticleVectors.ParticleVector, sample_every: int, dump_every: int, bin_size: Tuple[float, float, float] = (1.0, 1.0, 1.0), channels: List[Tuple[str, str]], path: str = 'xdmf/') -> Tuple[Plugins.Average3D, Plugins.UniformCartesianDumper]


        Create :any:`Average3D` plugin
        
        Args:
            name: name of the plugin
            pv: :any:`ParticleVector` that we'll work with
            sample_every: sample quantities every this many time-steps
            dump_every: write files every this many time-steps 
            bin_size: bin size for sampling. The resulting quantities will be *cell-centered*
            path: Path and filename prefix for the dumps. For every dump two files will be created: <path>_NNNNN.xmf and <path>_NNNNN.h5
            channels: list of pairs name - type.
                Name is the channel (per particle) name. Always available channels are:
                    
                * 'velocity' with type "float8"             
                * 'force' with type "float4"
                
                Type is to provide the type of quantity to extract from the channel.                                            
                Type can also define a simple transformation from the channel internal structure                 
                to the datatype supported in HDF5 (i.e. scalar, vector, tensor)                                  
                Available types are:                                                                             
                                                                                                                
                * 'scalar': 1 float per particle                                                                   
                * 'vector': 3 floats per particle                                                                  
                * 'vector_from_float4': 4 floats per particle. 3 first floats will form the resulting vector       
                * 'vector_from_float8' 8 floats per particle. 5th, 6th, 7th floats will form the resulting vector. 
                    This type is primarity made to be used with velocity since it is stored together with          
                    the coordinates as 8 consecutive float numbers: (x,y,z) coordinate, followed by 1 padding value
                    and then (x,y,z) velocity, followed by 1 more padding value                                    
                * 'tensor6': 6 floats per particle, symmetric tensor in order xx, xy, xz, yy, yz, zz
                
    

    """
    pass

def createDumpAverageRelative():
    r"""createDumpAverageRelative(compute_task: bool, name: str, pv: ParticleVectors.ParticleVector, relative_to_ov: ParticleVectors.ObjectVector, relative_to_id: int, sample_every: int, dump_every: int, bin_size: Tuple[float, float, float] = (1.0, 1.0, 1.0), channels: List[Tuple[str, str]], path: str = 'xdmf/') -> Tuple[Plugins.AverageRelative3D, Plugins.UniformCartesianDumper]


              
        Create :any:`AverageRelative3D` plugin
                
        The arguments are the same as for createDumpAverage() with a few additions
        
        Args:
            relative_to_ov: take an object governing the frame of reference from this :any:`ObjectVector`
            relative_to_id: take an object governing the frame of reference with the specific ID
    

    """
    pass

def createDumpMesh():
    r"""createDumpMesh(compute_task: bool, name: str, ov: ParticleVectors.ObjectVector, dump_every: int, path: str) -> Tuple[Plugins.MeshPlugin, Plugins.MeshDumper]


        Create :any:`MeshPlugin` plugin
        
        Args:
            name: name of the plugin
            ov: :any:`ObjectVector` that we'll work with
            dump_every: write files every this many time-steps
            path: the files will look like this: <path>/<ov_name>_NNNNN.ply
    

    """
    pass

def createDumpObjectStats():
    r"""createDumpObjectStats(compute_task: bool, name: str, ov: ParticleVectors.ObjectVector, dump_every: int, path: str) -> Tuple[Plugins.ObjPositions, Plugins.ObjPositionsDumper]


        Create :any:`ObjPositions` plugin
        
        Args:
            name: name of the plugin
            ov: :any:`ObjectVector` that we'll work with
            dump_every: write files every this many time-steps
            path: the files will look like this: <path>/<ov_name>_NNNNN.txt
    

    """
    pass

def createDumpXYZ():
    r"""createDumpXYZ(compute_task: bool, name: str, pv: ParticleVectors.ParticleVector, dump_every: int, path: str) -> Tuple[Plugins.XYZPlugin, Plugins.XYZDumper]


        Create :any:`XYZPlugin` plugin
        
        Args:
            name: name of the plugin
            pv: :any:`ParticleVector` that we'll work with
            dump_every: write files every this many time-steps
            path: the files will look like this: <path>/<pv_name>_NNNNN.xyz
    

    """
    pass

def createImposeProfile():
    r"""createImposeProfile(compute_task: bool, name: str, pv: ParticleVectors.ParticleVector, low: Tuple[float, float, float], high: Tuple[float, float, float], velocity: Tuple[float, float, float], kbt: float) -> Tuple[Plugins.ImposeProfile, Plugins.PostprocessPlugin]


        Create :any:`ImposeProfile` plugin
        
        Args:
            name: name of the plugin
            pv: :any:`ParticleVector` that we'll work with
            low: the lower corner of the domain
            high: the higher corner of the domain
            velocity: target velocity
            kbt: temperature in the domain (appropriate Maxwell distribution will be used)
    

    """
    pass

def createImposeVelocity():
    r"""createImposeVelocity(compute_task: bool, name: str, pv: ParticleVectors.ParticleVector, every: int, low: Tuple[float, float, float], high: Tuple[float, float, float], velocity: Tuple[float, float, float]) -> Tuple[Plugins.ImposeVelocity, Plugins.PostprocessPlugin]


        Create :any:`ImposeVelocity` plugin
        
        Args:
            name: name of the plugin
            pv: :any:`ParticleVector` that we'll work with
            every: change the velocities once in **every** timestep
            low: the lower corner of the domain
            high: the higher corner of the domain
            velocity: target velocity
    

    """
    pass

def createPinObject():
    r"""createPinObject(compute_task: bool, name: str, ov: ParticleVectors.ObjectVector, dump_every: int, path: str, pin_translation: Tuple[int, int, int], pin_rotation: Tuple[int, int, int]) -> Tuple[Plugins.PinObject, Plugins.ReportPinObject]


        Create :any:`PinObject` plugin
        
        Args:
            name: name of the plugin
            ov: :any:`ObjectVector` that we'll work with
            dump_every: write files every this many time-steps
            path: the files will look like this: <path>/<ov_name>_NNNNN.txt
            pin_translation: 3 integers; 0 means that motion along the corresponding axis is unrestricted,
                1 means fixed position wrt to the axis
            pin_rotation: 3 integers; 0 means that rotation along the corresponding axis is unrestricted,
                1 means fixed rotation wrt to the axis
    

    """
    pass

def createStats():
    r"""createStats(compute_task: bool, name: str, filename: str, every: int) -> Tuple[Plugins.SimulationStats, Plugins.PostprocessStats]


        Create :any:`SimulationStats` plugin
        
        Args:
            name: name of the plugin
            filename: the stats will also be recorded to that file in a computer-friendly way
            every: report to standard output every that many time-steps
    

    """
    pass

def createTemperaturize():
    r"""createTemperaturize(arg0: bool, arg1: str, arg2: ParticleVectors.ParticleVector, arg3: float, arg4: bool) -> Tuple[Plugins.Temperaturize, Plugins.PostprocessPlugin]


        TODO
    

    """
    pass

def createVelocityControl():
    r"""createVelocityControl(compute_task: bool, name: str, pv: ParticleVectors.ParticleVector, low: Tuple[float, float, float], high: Tuple[float, float, float], every: int, targetVel: Tuple[float, float, float], Kp: float, Ki: float, Kd: float) -> Tuple[Plugins.VelocityControl, Plugins.PostprocessPlugin]


        Create :any:`VelocityControl` plugin
        
        Args:
            name: name of the plugin
            pv: :class:`ParticleVector` that we'll work with
            low, high: boundaries of the domain of interest
            every: write files every this many time-steps
            targetVel: the target mean velocity of the particles in the domain of interest
            Kp, Ki, Kd: PID controller coefficients
    

    """
    pass

def createWallRepulsion():
    r"""createWallRepulsion(compute_task: bool, name: str, pv: ParticleVectors.ParticleVector, wall: Walls.Wall, C: float, h: float, max_force: float) -> Tuple[Plugins.WallRepulsion, Plugins.PostprocessPlugin]


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


