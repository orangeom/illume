#include "sphere.h"

Sphere* sphere_new(float r, Vector3 center, Material m)
{
	Sphere* sphere = (Sphere *) calloc(1, sizeof(Sphere));
	if (!sphere)
	{
		return NULL;
	}
	*sphere = sphere_create(r, center, m);
	return sphere;
}

void sphere_free(Sphere* sphere)
{
	if (sphere)
	{
		free(sphere);
	}
}

Sphere sphere_create(float r, Vector3 center, Material m)
{
	Sphere sphere;
	sphere.r = r;
	sphere.center = center;
	sphere.m = m;
	return sphere;
}

__device__
void sphere_ray_intersect(Sphere sphere, Ray ray, Hit* hit)
{
	Vector3 l = vector3_sub(sphere.center, ray.o);
	float s = vector3_dot(l, ray.d);
	float ls = vector3_dot(l, l);
	float rs = sphere.r * sphere.r;
	if (s < 0 && ls > rs)
	{
		hit_set_no_intersect(hit);
		return;
	}
	float ms = ls - s * s;
	if (ms > rs)
	{
		hit_set_no_intersect(hit);
		return;
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
	Vector3 pos = ray_position_along(ray, t);
	Vector3 normal = vector3_sub(pos, sphere.center);
	vector3_normalize(&normal);
	hit_set(hit, t, normal, sphere.m);
}
