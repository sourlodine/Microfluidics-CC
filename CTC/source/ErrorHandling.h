/*
 *  ErrorHandling.h
 *  rl
 *
 *  Created by Dmitry Alexeev on 03.05.13.
 *  Copyright 2013 ETH Zurich. All rights reserved.
 *
 */

#pragma once

#include <cstdlib>
#include <cstdio>

namespace ErrorHandling
{
	extern int debugLvl;
    extern int rank;
	
#define    die(format, ...) {if (ErrorHandling::rank == 0) fprintf(stderr, format, ##__VA_ARGS__), abort();}
#define  error(format, ...) {if (ErrorHandling::rank == 0) fprintf(stderr, format, ##__VA_ARGS__);}
	
#define   warn(format, ...)	{if (ErrorHandling::rank == 0 && ErrorHandling::debugLvl > 0) fprintf(stderr, format, ##__VA_ARGS__);}
#define   info(format, ...)	{if (ErrorHandling::rank == 0 && ErrorHandling::debugLvl > 1) fprintf(stderr, format, ##__VA_ARGS__);}

#define  debug(format, ...)	{if (ErrorHandling::rank == 0 && ErrorHandling::debugLvl > 2) fprintf(stderr, format, ##__VA_ARGS__);}
#define debug1(format, ...)	{if (ErrorHandling::rank == 0 && ErrorHandling::debugLvl > 3) fprintf(stderr, format, ##__VA_ARGS__);}
#define debug2(format, ...)	{if (ErrorHandling::rank == 0 && ErrorHandling::debugLvl > 4) fprintf(stderr, format, ##__VA_ARGS__);}
#define debug3(format, ...)	{if (ErrorHandling::rank == 0 && ErrorHandling::debugLvl > 5) fprintf(stderr, format, ##__VA_ARGS__);}
#define debug4(format, ...)	{if (ErrorHandling::rank == 0 && ErrorHandling::debugLvl > 6) fprintf(stderr, format, ##__VA_ARGS__);}
#define debug5(format, ...)	{if (ErrorHandling::rank == 0 && ErrorHandling::debugLvl > 7) fprintf(stderr, format, ##__VA_ARGS__);}
}