#ifndef _KERNEL_
#define _KERNEL_

#include <stdlib.h>
#include <stdio.h>

#include <curand.h>
#include <curand_kernel.h>

#include "accel/kdtree.h"
#include "math/vector3.h"
#include "math/ray.h"
#include "math/constants.h"
#include "math/sample.h"
#include "primitives/plane.h"
#include "primitives/sphere.h"
#include "primitives/mesh.h"
#include "primitives/mesh_instance.h"
#include "bitmap.h"
#include "scene/scene.h"
#include "material.h"
#include "error_check.h"
#include "camera.h"

#ifdef __cplusplus
extern "C" {
#endif

void  render_scene  (Scene* scene, Bitmap* bitmap, Camera camera, int samples, int max_depth);

#ifdef __cplusplus
}
#endif

#endif