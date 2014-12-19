/*
 *  timer.h
 *  hw
 *
 *  Created by Dmitry Alexeev on 30.10.12.
 *  Copyright 2012 ETH Zurich. All rights reserved.
 *
 */

#pragma once

#include <unistd.h>
#include <ctype.h>
#include <stdlib.h>

#ifndef __APPLE__
#include <ctime>
inline long int mach_absolute_time()
{
	timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return (long int) (t.tv_sec*1e9 + t.tv_nsec);
}
#else
#include <mach/mach.h>
#include <mach/mach_time.h>
#endif

class Timer
{
private:
	long int _start, _end;
	
public:
	
	Timer()
	{
		_start = 0;
		_end = 0;
	}
	
	void start()
	{
		_start = mach_absolute_time();
		_end = 0;
	}
	
	void stop()
	{
		_end = mach_absolute_time();
	}
	
	long int elapsed()
	{
		if (_end == 0) _end = mach_absolute_time();
		return _end - _start;
	}
	
	long int elapsedAndReset()
	{
		if (_end == 0) _end = mach_absolute_time();
		long int t = _end - _start;
		_start = _end;
		_end = 0;
		return t;
	}
	
};
