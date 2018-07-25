#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Fri Jul  6 14:10:53 2018

@author: alexeedm
"""
import inspect
import functools
import sys

from libudevicex import *


# Global variable for the udevicex coordination class
# Used in decorators to access compute task status
__coordinator = None

# Wrap the creation of all the simulation handlers
# and particle vectors.
# If we are not a compute task, just return None
def decorate_none_if_postprocess(f):
    @functools.wraps(f)
    def wrapper(*args, **kwargs):
        global __coordinator
        if __coordinator.isComputeTask():
            return f(*args, **kwargs)
        else:
            return None
    return wrapper

# Wrap the creation of plugins
# Pass the compute task status into the creation function
def decorate_coordinator(f):
    @functools.wraps(f)
    def wrapper(self, *args, **kwargs):
        global __coordinator
        f(self, *args, **kwargs)

        if __coordinator is not None:
            raise Exception('There can only be one coordinator at a time!')
        __coordinator = self

    return wrapper

# Wrap the registration of the plugins
def decorate_register_plugins(f):
    @functools.wraps(f)
    def wrapper(self, plugins_tuple):
        return f(self, plugins_tuple[0], plugins_tuple[1])

    return wrapper


# Wrap the creation of the coordinator
def decorate_plugins(f):
    @functools.wraps(f)
    def wrapper(*args, **kwargs):
        global __coordinator
        return f(__coordinator.isComputeTask(), *args, **kwargs)

    return wrapper


def __init__():
    # Wrap everything except for plugins
    # Make the __init__ functions return None if we are not a compute task
    classes = {}
    submodules =  inspect.getmembers(sys.modules[__name__],
                                    lambda member: inspect.ismodule(member)
                                    and 'udevicex' in member.__name__ )
    for m in submodules:
        classes[m[0]] = inspect.getmembers(sys.modules[m[1].__name__],
                                        lambda member: inspect.isclass(member)
                                        and 'udevicex' in member.__module__ )

    for module in classes.keys():
        if module != 'Plugins':
            for cls in classes[module]:
                setattr(cls[1], '__new__', decorate_none_if_postprocess(cls[1].__new__))

    # Now wrap plugins creation
    # Also change the names of the function
    # by removing the double underscore
    for m in submodules:
        if m[0] == 'Plugins':
            funcs = inspect.getmembers(sys.modules[m[1].__name__],
                                        lambda member: inspect.isbuiltin(member)
                                        and 'udevicex' in member.__module__)
            
            
            for f in funcs:
                if '__create' in f[0]:
                    setattr(m[1], f[0][2:], decorate_plugins(f[1]))

    # Wrap initialization of the udevicex coordinator
    udevicex.__init__ = decorate_coordinator(udevicex.__init__)
    
    # Wrap registration of the plugins
    udevicex.registerPlugins = decorate_register_plugins(udevicex.registerPlugins)


__init__()
