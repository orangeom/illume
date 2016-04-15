#ifndef _SPHERE_
#define _SPHERE_

#include "../math/vector3.h"
#include "../math/ray.h"
#include "../intersection.h"
#include "../material.h"

typedef struct
{
	float r;
	Vector3 center;
	Material m;
} 
Sphere;

#ifdef __cplusplus
extern "C" {
#endif
          
            Sphere        sphere_create         (float r, Vector3 center, Material m);
__device__  Intersection  sphere_ray_intersect  (Sphere sphere, Ray ray);

#ifdef __cplusplus
}
#endif

#endif