#include "sphere.h"

Sphere* sphere_new(float r, Vector3 center)
{
	Sphere* sphere = (Sphere *) calloc(sizeof(Sphere), 1);
	if (!sphere)
	{
		return NULL;
	}
	sphere->r = r;
	sphere->center = center;
	return sphere;
}

void sphere_free(Sphere* sphere)
{
	if (sphere)
	{
		free(sphere);
	}
}

__device__
Intersection sphere_ray_intersection(Sphere* sphere, Ray* ray)
{
	 Vector3 l = vector3_sub(&sphere->center, &ray->o);
	 float s = vector3_dot(&l, &ray->d);
	 float ls = vector3_dot(&l, &l);
	 float rs = sphere->r * sphere->r;
	 if (s < 0 && ls > rs)
	 {
	 	return intersection_create(0);
	 }
	 float ms = ls - s * s;
	 if (ms > rs)
	 {
	 	return intersection_create(0);
	 }
	 float q = sqrtf(rs - ms);
	 float t = s;
	 if (ls > rs)
	 {
	 	t -= q;
	 }
	 else
	 {
	 	t += q;
	 }
	 return intersection_create(1);
}