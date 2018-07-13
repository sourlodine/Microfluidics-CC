.. _user-install:

Installation
############

uDeviceX requires at least Kepler-generation NVIDIA GPU and depends on a few external tools and libraries:

- Unix-based OS
- NVIDIA CUDA toolkit version >= 8.0
- gcc compiler with c++11 support compatible with CUDA installation
- CMake version >= 3.8
- Python interpreter version >= 2.7
- MPI library
- HDF5 parallel library
- libbfd for pretty debug information in case of crash

With all the prerequisites installed, you can take the following steps to run uDeviceX:

#. Get the up-to-date version of the code:

   .. code-block:: console
      
      $ git clone https://github.com/dimaleks/uDeviceX.git udevicex

#. Navigate to the udevicex folder, create a build folder and run CMake:

   .. code-block:: console
      
      $ cd udevicex
      $ mkdir build/
      $ cd build
      $ cmake ../src
   
   If CMake reports some packages are not found, make sure you have all the prerequisites installed and corresponding modules loaded.
   If that doesn't help, or you have some packages installed in non-default locations,
   you will need to manually point CMake to correct locations.
   
   See CMake documentation for more details on how to provide package installation files
   
   .. note::
      On CRAY systems you may need to tell CMake to dynamically link the libraries by the following flag:
      
      .. code-block:: console
      
         $ cmake -DCMAKE_EXE_LINKER_FLAGS="-dynamic" ../src
   
#. Now you can compile the code:

   .. code-block:: console
      
      $ make -j <number_of_jobs> 
   
   The library will be generated in the current build folder.
   You can import it as a regular python module by providing Python with the path to the build folder:
   
   .. code-block:: python
      
      import sys
      sys.path.append('/path/to/installation/udevicex/build')
      import _udevicex as udx
   
