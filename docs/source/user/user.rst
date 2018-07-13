.. _user-all:

User guide
##########

This section describes the uDeviceX interface and introduces the reader to installing and running the code.
   
.. toctree::
   :maxdepth: 1
   :caption: Python API
   
   ./installation
   ./benchmarks
   ./udevicex
   ./particle_vectors
   ./initial_conditions
   ./interactions
   ./integrators
   ./walls
   ./bouncers
   ./object_belonging
   ./plugins

The uDeviceX code is designed as a classical molecular dynamics code adapted for inclusion rigid bodies and cells.
The simulation consists of multiple time-steps during which the particles and bodies will be displaces following laws of mechanics and hydrodynamics.
One time-step roughly consists of the following steps:

* compute all the forces in the system, which are mostly pairwise forces between different particles,
* move the particles by integrating the equations of motions,
* bounce particles off the wall surfaces so that they cannot penetrate the wall even in case of soft-core interactions,
* bounce particles off the bodies (i.e. rigid bodies and elastic membranes),
* perform additional operations dictated by plug-ins (modifications, statistics, data dumps, etc.).

Python scripts
***************

The code uses Python scripting language for the simulation setup.
The script defines simulation domain, number of MPI ranks to run; data containers, namely :ref:`user-pv` and data handlers: 
:ref:`user-ic`, :ref:`user-integrators`, :ref:`user-interactions`, :ref:`user-walls`, :ref:`user-bouncers`, :ref:`user-belongers` and :ref:`user-plugins`.
A simple script looks this way:
   
.. role:: bash(code)
   :language: bash

.. code-block:: python

   #TODO add example

General setup
=============


+-----------+----------+---------+-----------------------------------------------------------+
| Attribute | Type     | Default | Remarks                                                   |
+===========+==========+=========+===========================================================+
| name      | string   | ""      | Simulation name, doesn't influence anything at the moment |
+-----------+----------+---------+-----------------------------------------------------------+
| logfile   | string   | "log"   | Prefix of the log files to be created.                    |
+-----------+----------+---------+-----------------------------------------------------------+
| mpi_ranks | integer3 | (1,1,1) | Number of MPI ranks along each dimension.                 |
+-----------+----------+---------+-----------------------------------------------------------+
| debug_lvl | integer  | 2       | Level of logging verbosity                                |
+-----------+----------+---------+-----------------------------------------------------------+

Logging is implemented in the form of one file per MPI rank,
so in the simulation folder NP files with names log_00000.log, log_00001.log, ... will be created, where NP is the total number of MPI ranks.
Each process writes messages about himself into his own log file,
and the combined log may be created by merging all the individual ones and sorting with respect to time.

Debug level varies from 1 to 8:

#. only report fatal errors
#. report serious errors
#. report warnings (this is the default level)
#. report not critical information
#. report some debug information
#. report more debug
#. report all the debug
#. force flushing to the file after each message

Debug levels above 4 or 5 may significanlty increase the runtime, they are only recommended to debug errors.
Flushing increases the runtime yet more, but it is required in order not to lose any messages in case of abnormal program abort.

Domain
======

The domain is defined by the domain node with one attribute size taking 3 numbers as domain sizes along the three axes.
The domain will be split in equal chunks between the MPI ranks.
The largest chunk size that a single MPI rank can have depends on the total number of particles,
handlers and hardware, and is typically about :math:`120^3 - 200^3`.


Running the simulation
**********************

The executable :bash:`udevicex` takes only one parameter passed by :bash:`-i` or :bash:`--input` key, which is the path to the script.
The typical execution command with the script listed above looks as follows:

.. code-block:: bash

   mpirun -np 12 ./udevicex -i script.xml

You have to submit twice as more MPI tasks as specified in the script, because every second rank is only responsible for running some plugins and dumping data.
Recommended strategy is to place two tasks per single compute node with one GPU or 2 tasks pers one GPU in multi-GPU configuration.
The postprocessing tasks will not use any GPU calls, so you may not need multiprocess GPU mode or MPS.

If the code is started with number of tasks exactly equal to the number specified in the script, the postprocessing will be disabled.
All the plugins that use the postprocessing will not work.
This execution mode is mainly aimed at debugging.

