.. _user-pv:

Particle Vectors
################

Particle Vector (or *PV*) is collection of particles in the simulation with identical properties.
PV is the minimal unit of particles that can be addressed by most of the processing utilities,
i.e. it is possible to specify interactions between different (or same) PVs, apply integrators, plugins, etc. to the PVs.

Object Vector (or *OV*) is a Particle Vector with the particles separated into groups (*objects*) of the **same size**.
Objects are assumed to be spatially localized, so they always fully reside of a single MPI process.
OV can be used in most of the places where a regular PV is used, and more

Syntax
******

.. role:: xml(code)
   :language: xml

.. code-block:: xml

   <particle_vector attributes="...">
      <generate />
   </particle_vector>

.. note::
   :xml:`generate` node defines the way the particles will be generated.
   Syntax and meaning of the :xml:`generate` are described in the :ref:`user-ic` section

Common attributes
*****************

+------------------+---------+---------+---------------------------------------------------------------+
| Attribute        | Type    | Default | Remarks                                                       |
+==================+=========+=========+===============================================================+
| type             | string  | ""      | Type of the PV, see below for the                             |
|                  |         |         | list of available types                                       |
+------------------+---------+---------+---------------------------------------------------------------+
| name             | string  | ""      | Name of the created PV                                        |
+------------------+---------+---------+---------------------------------------------------------------+
| mass             | float   | 1.0     | Mass of a single particle in the PV                           |
+------------------+---------+---------+---------------------------------------------------------------+
| checkpoint_every | integer | 0       | Every that many timesteps the state of the Particle Vector    |
|                  |         |         | across all the MPI processes will be saved to disk            |
|                  |         |         | into the ./restart/ folder. The checkpoint files may be used  |
|                  |         |         | to restart the whole simulation or only some individual PVs   |
|                  |         |         | from the saved states. Default value of 0 means no checkpoint |
+------------------+---------+---------+---------------------------------------------------------------+


Available Particle Vectors
**************************

* **Regular Particle Vector**

   Type: *regular*
   
   This is the basic Particle Vector, with no additional attributes provided.
   
   **Example**
   
   
   .. code-block:: xml
   
      <particle_vector type="regular" name="dpd" mass="1"  >
         <generate type="uniform" density="8" />
      </particle_vector>

* **Membrane**

   Type: *membrane*
   
   Membrane is an Object Vector representing cell membranes.
   It must have a triangular mesh associated with it such that each particle is mapped directly onto single mesh vertex.
   
   Additional attributes:
   
   +-------------------+---------+----------+----------------------------------------------+
   | Attribute         | Type    | Default  | Remarks                                      |
   +===================+=========+==========+==============================================+
   | particles_per_obj | integer | 1        | Number of the particles making up one cell   |
   +-------------------+---------+----------+----------------------------------------------+
   | mesh_filename     | string  |          | Path to the .OFF mesh file, see `OFF mesh`.  |
   |                   |         | mesh.off | The number of vertices of the mesh should be |
   |                   |         |          | equal to :xml:`particles_per_obj`.           |
   +-------------------+---------+----------+----------------------------------------------+
                                  
    **Example**                   
                                  
   .. code-block:: xml            
                                  
      <particle_vector type="membrane" name="rbcs" mass="1.0" particles_per_obj="498" mesh_filename="rbc_mesh.off"  >
         <generate type="restart" path="restart/" />
      </particle_vector>
      
* **Rigid object**

   Type: *rigid_objects*
   
   Rigid Object is an Object Vector representing objects that move as rigid bodies, with no relative displacement against each other in an object.
   It must have a triangular mesh associated with it that defines the shape of the object.
   
   Additional attributes:
   
   +-------------------+---------+-----------+----------------------------------------------------------------------------------------------+
   | Attribute         | Type    | Default   | Remarks                                                                                      |
   +===================+=========+===========+==============================================================================================+
   | particles_per_obj | integer | 1         | Number of the particles making up one cell                                                   |
   +-------------------+---------+-----------+----------------------------------------------------------------------------------------------+
   | mesh_filename     | string  |           | Path to the .OFF mesh file, see `OFF mesh`.                                                  |
   |                   |         | mesh.off  | The number of vertices of the mesh should be                                                 |
   |                   |         |           | equal to :xml:`particles_per_obj`.                                                           |
   +-------------------+---------+-----------+----------------------------------------------------------------------------------------------+
   | moment_of_inertia | float3  | (1, 1, 1) | Moment of inertia of the body in its principal axes                                          |
   |                   |         |           | The principal axes of the mesh are assumed to be aligned with the default global *OXYZ* axes |
   +-------------------+---------+-----------+----------------------------------------------------------------------------------------------+
   
   **Example**
   
   .. code-block:: xml
   
      <particle_vector type="rigid_objects" name="blob" mass="1.0" particles_per_obj="4242" moment_of_inertia="67300 45610 34300" mesh_filename="blob.off" >
          <generate type="read_rigid" ic_filename="blob.ic" xyz_filename="blob.xyz"/>
      </particle_vector>

   
* **Rigid ellipsoid**

   Type: *rigid_ellipsoids*
   
   Rigid Ellipsoid is the same as the Rigid Object except that it can only represent ellipsoidal shapes.
   The advantage is that it doesn't need mesh and moment of inertia define, as those can be computed analytically.
   
   Additional attributes:
   
   +-------------------+---------+-----------+--------------------------------------------+
   | Attribute         | Type    | Default   | Remarks                                    |
   +===================+=========+===========+============================================+
   | particles_per_obj | integer | 1         | Number of the particles making up one cell |
   +-------------------+---------+-----------+--------------------------------------------+
   | axes              | float3  | (1, 1, 1) | Ellipsoid principal semi-axes              |
   +-------------------+---------+-----------+--------------------------------------------+
   
   **Example**                   
   
   .. code-block:: xml
   
      <particle_vector type="rigid_ellipsoids" name="sphere" mass="1.847724" particles_per_obj="2267" axes="5 5 5" >
           <generate type="read_rigid" ic_filename="sphere.ic" xyz_filename="sphere.xyz" />
      </particle_vector>
      

      
