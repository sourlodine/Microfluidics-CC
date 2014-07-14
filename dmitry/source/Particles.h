//
//  Particles.h
//  CTC
//
//  Created by Dmitry Alexeev on 09.07.14.
//  Copyright (c) 2014 Dmitry Alexeev. All rights reserved.
//

#ifndef CTC_Particles_h
#define CTC_Particles_h


//**********************************************************************************************************************
// Particles
//
// Structure of arrays is used for efficient the computations
//**********************************************************************************************************************
struct Particles
{
	double *x,  *y,  *z;
	double *vx, *vy, *vz;
	double *ax, *ay, *az;
	double *m;
	double *tmp;
	int n;
};


#endif
