#ifndef _MATRIX4_
#define _MATRIX4_

#include "vector3.h"
#include <stdio.h>

const int SUB[4][3] = 
{
	{1, 2, 3},	
    {0, 2, 3},
    {0, 1, 3},
    {0, 1, 2}
};

typedef struct
{
	float m[4][4];
}
Matrix4;

#ifdef __cplusplus
extern "C" {
#endif

			void     matrix4_print          (Matrix4 m);
            Matrix4  matrix4_create         ();
            void     matrix4_set_scale      (Matrix4* m, Vector3 scale);
            void     matrix4_set_translate  (Matrix4* m, Vector3 translation);
            Matrix4  matrix4_mul            (Matrix4 a, Matrix4 b);
            Matrix4  matrix4_get_transpose  (Matrix4 m);
            Matrix4  matrix4_get_inverse    (Matrix4 m);
__device__  Vector3  matrix4_mul_vector3    (Matrix4 m, Vector3 v, float w);

#ifdef __cplusplus
}
#endif

#endif