#ifndef _PLANE_
#define _PLANE_

#include "../math/vector3.h"
#include "../math/ray.h"
#include "../material.h"
#include "../intersection.h"

typedef struct
{
	Vector3 p;
	Vector3 n;
	Material m;
}
Plane;

#ifdef __cplusplus
extern "C" {
#endif

            Plane*        plane_new            (Vector3 p, Vector3 n, Material m);
            void          plane_free           (Plane* plane);
            Plane         plane_create         (Vector3 p, Vector3 n, Material m);
__device__  Intersection  plane_ray_intersect  (Plane plane, Ray r);

#ifdef __cplusplus
}
#endif

#endif
