#ifndef _MESH_
#define _MESH_

#include <stdio.h>
#include <string.h>
#include <float.h>

#include "triangle.h"
#include "../arraylist.h"
#include "../math/vector3.h"
#include "../math/ray.h"
#include "../intersection.h"

static const int OBJ_TOKENS = 4;
static const int VERTEX_COMPONENTS = 4;
static const int FACE_COMPONENTS = 4;
static const char* TOKEN_VERTEX = "v";
static const char* TOKEN_FACE = "f";

typedef struct
{
	int triangle_amount;
	Triangle* triangles;
}
Mesh;

#ifdef __cplusplus
extern "C" {
#endif


            Mesh*         mesh_new            (const char* path);
            void          mesh_free           (Mesh* mesh);
__device__  Intersection  mesh_ray_intersect  (Mesh mesh, Ray ray);

#ifdef __cplusplus
}
#endif

#endif