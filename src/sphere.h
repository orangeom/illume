#ifndef _SPHERE_
#define _SPHERE_

#include "intersection.h"
#include "vector3.h"
#include "ray.h"

typedef struct
{
	float r;
	Vector3 center;
} 
Sphere;
          
            Sphere*       sphere_new               (float r, Vector3 center);
            void          sphere_free              (Sphere* sphere);
__device__  Intersection  sphere_ray_intersection  (Sphere* sphere, Ray* ray);

#endif