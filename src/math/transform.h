#ifndef _TRANSFORM_
#define _TRANSFORM_

#include "rapidjson\document.h"

#include "matrix4.h"
#include "vector3.h"

typedef struct
{
	Matrix4 mat;
	Matrix4 inv;
	Matrix4 trans;
	Matrix4 trans_inv;
}
Transform;

#ifdef __cplusplus
extern "C" {
#endif

Transform  transform_create     (Vector3 translation, Vector3 scale, Matrix4 rotation);
Transform  transform_from_json  (rapidjson::Value& json);

#ifdef __cplusplus
}
#endif

#endif