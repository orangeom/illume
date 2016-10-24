#include "kernel.h"

#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>

#include <curand.h>
#include <curand_kernel.h>

#include "error_check.h"
#include "material.h"
#include "primitives/plane.h"
#include "primitives/sphere.h"
#include "primitives/mesh.h"
#include "primitives/mesh_instance.h"
#include "math/sample.h"
#include "math/vector3.h"
#include "math/ray.h"
#include "math/constants.h"
#include "math/matrix4.h"
#include "accel/bvh.h"

#include "intellisense.h"

__global__ 
void init_curand_states(curandState* states, uint32_t hash, int N)
{
	int index = blockIdx.x * blockDim.x + threadIdx.x;
	if (index < N)
	{
		curand_init(hash + index, 0, 0, &states[index]);
	}
}

typedef struct
{
	float image_width;
	Camera camera;
	float camera_pixel_size;
	float camera_left;
	float camera_top;
} 
RenderInfo;

__global__
void init_rays(Ray* rays, int* ray_statuses, Vector3* ray_colors, RenderInfo* info, curandState* states, int N)
{
	int index = blockIdx.x * blockDim.x + threadIdx.x;
	if (index < N)
	{
		RenderInfo i = *info;
		int x = index % (int) i.image_width;
		int y = index / (int) i.image_width;
		float left_edge = i.camera_left + i.camera_pixel_size * (float) x;
		float top_edge = i.camera_top - i.camera_pixel_size * (float) y;

		float r_x = left_edge + i.camera_pixel_size * curand_uniform(&states[index]);
		float r_y = top_edge - i.camera_pixel_size * curand_uniform(&states[index]);

		Vector3 pos = vector3_create(0, 0, 0);
		if (i.camera.aperture > FLT_EPSILON)
		{
			float u1 = curand_uniform(&states[index]);
			float u2 = curand_uniform(&states[index]);
			pos = vector3_mul(sample_circle(u1, u2), i.camera.aperture);
		}
		Vector3 origin = matrix4_mul_vector3(&i.camera.transform, pos, 1.f);
		Vector3 image_pos = matrix4_mul_vector3(&i.camera.transform, vector3_create(r_x, r_y, i.camera.dof), 1.f);
		rays[index] = ray_create(origin, vector3_sub(image_pos, origin));
		ray_statuses[index] = index;
		ray_colors[index] = vector3_create(1, 1, 1);
	}
}

__device__
static Hit get_min_hit(Scene* scene, Ray ray)
{
	Hit min = hit_create_no_intersect();
	min.d = FLT_MAX;
	for (int i = 0; i < scene->sphere_amount; i++)
	{
		Hit inter = sphere_ray_intersect(scene->spheres[i], ray);

		if (inter.is_intersect == 1 && inter.d < min.d)
		{
			min = inter;
		}
	}

	for (int i = 0; i < scene->plane_amount; i++)
	{
		Hit inter = plane_ray_intersect(scene->planes[i], ray);

		if (inter.is_intersect == 1 && inter.d < min.d)
		{
			min = inter;
		}
	}

	for (int i = 0; i < scene->instance_amount; i++)
	{
		int mesh_index = scene->instances[i].mesh_index;
		Hit inter =
			mesh_instance_ray_intersect(scene->instances + i, scene->meshes + mesh_index, ray);

		if (inter.is_intersect == 1 && inter.d < min.d)
		{
			min = inter;
		}
	}

	return min;
}

__global__
void pathtrace_kernel(Vector3* final_colors, Ray* rays, int* ray_statuses,
Vector3* ray_colors, Scene* scene, curandState* states, int N)
{
	int index = blockDim.x * blockIdx.x + threadIdx.x;
	int ray_index = ray_statuses[index];

	if (index < N && ray_index != -1)
	{
		Scene local_scene = *scene;
		Hit min = get_min_hit(&local_scene, rays[ray_index]);

		if (min.is_intersect == 1)
		{
			Ray r = rays[ray_index];
			Vector3 new_dir;
			Vector3 norm_o = vector3_mul(min.normal, vector3_dot(min.normal, r.d) > 0 ? -1.0f : 1.0f);
			Vector3 new_origin = ray_position_along(r, min.d);
			vector3_add_to(&new_origin, vector3_mul(norm_o, 10e-6));

			if (min.m.type == MATERIAL_EMISSIVE)
			{
				vector3_mul_vector_to(&ray_colors[ray_index], min.m.c);
				vector3_add_to(&final_colors[ray_index], ray_colors[ray_index]);
				ray_statuses[index] = -1;
				new_dir = vector3_create(0, 0, 0);
			}
			else if (min.m.type == MATERIAL_DIFFUSE)
			{
				vector3_mul_vector_to(&ray_colors[ray_index], min.m.c);
				float u1 = curand_uniform(&states[ray_index]);
				float u2 = curand_uniform(&states[ray_index]);
				Vector3 sample = sample_hemisphere_cosine(u1, u2);
				new_dir = vector3_to_basis(sample, norm_o);

			}
			else if (min.m.type == MATERIAL_SPECULAR)
			{
				vector3_mul_vector_to(&ray_colors[ray_index], min.m.c);
				new_dir = vector3_reflect(r.d, norm_o);
			}
			else if (min.m.type == MATERIAL_REFRACTIVE)
			{
				bool into = vector3_dot(min.normal, norm_o) > 0.0f;
				float nc = 1.0f;
				float nt = 1.5f;
				float nnt = into ? nc / nt : nt / nc;
				float ddn = vector3_dot(r.d, norm_o);
				float cos2t = 1.0f - nnt * nnt * (1.0f - ddn * ddn);
				if (cos2t < 0.0f)
				{
					new_dir = vector3_reflect(r.d, min.normal);
				}
				else
				{
					Vector3 tdir = vector3_sub(vector3_mul(r.d, nnt), vector3_mul(min.normal, (into ? 1.0f : -1.0f) * (ddn * nnt + sqrtf(cos2t))));
					vector3_normalize(&tdir);
					float a = nt - nc;
					float b = nt + nc;
					float r0 = (a * a) / (b * b);
					float c = 1.0f - (into ? -ddn : vector3_dot(tdir, min.normal));
					float re = r0 + (1.0f - r0) * c * c * c * c *c;
					float tr = 1.0f - re;
					float p = 0.25f + 0.5f * re;
					float rp = re / p;
					float tp = tr / (1.0f - p);

					if (curand_uniform(&states[ray_index]) < p)
					{
						ray_colors[ray_index] = vector3_mul(ray_colors[ray_index], rp);
						new_dir = vector3_reflect(r.d, min.normal);
					}
					else
					{
						ray_colors[ray_index] = vector3_mul(ray_colors[ray_index], tp);
						new_dir = tdir;
						vector3_add_to(&new_origin, vector3_mul(norm_o, -0.001));

					}
				}
			}

			ray_set(&rays[ray_index], new_origin, new_dir);
		}
		else
		{
			vector3_mul_vector_to(&ray_colors[ray_index], scene->sky_color);
			vector3_add_to(&final_colors[ray_index], ray_colors[ray_index]);
			ray_statuses[index] = -1;
		}


	}
}

static void compact_pixels(int* d_ray_statuses, int* h_ray_statuses, int* active_pixels)
{
	int pixels = *active_pixels;
	int size = pixels * sizeof(int); 
	HANDLE_ERROR( cudaMemcpy(h_ray_statuses, d_ray_statuses, size, cudaMemcpyDeviceToHost) );

	int left = 0;
	int right = pixels - 1;
	while (left < right)
	{
		while (h_ray_statuses[left] != -1 && left < pixels)
		{
			left++;
		}
		while (h_ray_statuses[right] == -1 && right >= 0)
		{
			right--;
		}

		if (left < right)
		{
			h_ray_statuses[left] = h_ray_statuses[right];
			h_ray_statuses[right] = -1;
		}
	}

	left = 0;
	while (left < pixels && h_ray_statuses[left] != -1)
	{
		left++;
	}
	*active_pixels = left;

	HANDLE_ERROR( cudaMemcpy(d_ray_statuses, h_ray_statuses, size, cudaMemcpyHostToDevice) );
}

__global__
void set_bitmap(Vector3* final_colors, Pixel* pixels, float samples, int N)
{
	int index = blockDim.x * blockIdx.x + threadIdx.x;
	if (index < N)
	{
		float gamma = 1 / 2.2;
		Vector3 corrected = vector3_mul(final_colors[index], 1 / samples);
		corrected = vector3_max(vector3_min(corrected, 1), 0);
		corrected = vector3_pow(corrected, gamma);
		pixels[index].red = (int) (255 * corrected.x);
		pixels[index].green = (int) (255 * corrected.y);
		pixels[index].blue = (int) (255 * corrected.z);
	}
}

static RenderInfo* allocate_render_info_gpu(int width, int height, Camera camera)
{
	RenderInfo i;
	i.image_width = width;
	float dim_ratio = (float) height / (float) width;
	float tan_half_fov = tanf(ILLUME_PI * camera.fov / 360);
	i.camera = camera;
	float dofmfov = camera.dof * tan_half_fov;
	i.camera_pixel_size = dofmfov * 2 / (float) width;
	i.camera_left = -1 * dofmfov;
	i.camera_top = dim_ratio * dofmfov;
	RenderInfo *d_info;
	HANDLE_ERROR( cudaMalloc(&d_info, sizeof(RenderInfo)) );
	HANDLE_ERROR( cudaMemcpy(d_info, &i, sizeof(RenderInfo), cudaMemcpyHostToDevice) );
	return d_info;
}

static Vector3* allocate_final_colors_gpu(int pixels_amount)
{
	Vector3* h_final_colors = (Vector3 *) malloc(sizeof(Vector3) * pixels_amount);
	for (int i = 0; i < pixels_amount; i++)
	{
		h_final_colors[i] = vector3_create(0, 0, 0);
	}
	Vector3* d_final_colors;
	HANDLE_ERROR( cudaMalloc(&d_final_colors, pixels_amount * sizeof(Vector3)) );
	HANDLE_ERROR( cudaMemcpy(d_final_colors, h_final_colors, pixels_amount * sizeof(Vector3), cudaMemcpyHostToDevice) );
	free(h_final_colors);
	return d_final_colors;
}

typedef struct
{
	Scene* d_scene;
	Sphere* d_spheres;
	Plane* d_planes;
	Mesh* d_meshes;
	int mesh_amount;
	Triangle** d_triangle_pointers;
	MeshInstance* d_instances;
	GPUNode** d_bvh_nodes;
	int** d_bvh_indices;
} 
SceneReference;

static SceneReference allocate_scene_gpu(Scene* scene)
{
	SceneReference ref;
	int spheres_size = sizeof(Sphere) * scene->sphere_amount;
	int planes_size = sizeof(Plane) * scene->plane_amount;
	int meshes_size = sizeof(Mesh) * scene->mesh_amount;
	int instances_size = sizeof(MeshInstance) * scene->instance_amount;
	ref.mesh_amount = scene->mesh_amount;

	HANDLE_ERROR( cudaMalloc(&ref.d_scene, sizeof(Scene)) );
	HANDLE_ERROR( cudaMalloc(&ref.d_spheres, spheres_size) );
	HANDLE_ERROR( cudaMalloc(&ref.d_planes, planes_size) );
	HANDLE_ERROR( cudaMalloc(&ref.d_instances, instances_size) );
	HANDLE_ERROR( cudaMalloc(&ref.d_meshes, meshes_size) );
	ref.d_triangle_pointers = (Triangle **) calloc(scene->mesh_amount, sizeof(Triangle *));
	Triangle** h_triangle_pointers = (Triangle **) calloc(scene->mesh_amount, sizeof(Triangle *));

	ref.d_bvh_nodes = (GPUNode **) calloc(scene->mesh_amount, sizeof(GPUNode*));
	GPUNode** h_bvh_nodes = (GPUNode **) calloc(scene->mesh_amount, sizeof(GPUNode*));
	ref.d_bvh_indices = (int **) calloc(scene->mesh_amount, sizeof(int*));
	int** h_bvh_indices = (int **) calloc(scene->mesh_amount, sizeof(int*));

	for (int i = 0; i < scene->mesh_amount; i++)
	{
		Mesh* mesh_p = &scene->meshes[i];
		Mesh mesh = *mesh_p;

		int triangles_size = mesh.triangle_amount * sizeof(Triangle);
		HANDLE_ERROR( cudaMalloc(&ref.d_triangle_pointers[i], triangles_size) );
		HANDLE_ERROR( cudaMemcpy(ref.d_triangle_pointers[i], mesh.triangles, triangles_size, cudaMemcpyHostToDevice) );
		h_triangle_pointers[i] = mesh.triangles;
		mesh_p->triangles = ref.d_triangle_pointers[i];	

		int nodes_size = mesh.bvh.node_amount * sizeof(GPUNode);
		HANDLE_ERROR(cudaMalloc(&ref.d_bvh_nodes[i], nodes_size));
		HANDLE_ERROR(cudaMemcpy(ref.d_bvh_nodes[i], mesh.bvh.nodes, nodes_size, cudaMemcpyHostToDevice));
		h_bvh_nodes[i] = mesh.bvh.nodes;
		mesh_p->bvh.nodes = ref.d_bvh_nodes[i];

		int indices_size = mesh.bvh.tri_index_amount * sizeof(int);
		HANDLE_ERROR(cudaMalloc(&ref.d_bvh_indices[i], indices_size));
		HANDLE_ERROR(cudaMemcpy(ref.d_bvh_indices[i], mesh.bvh.tri_indices, indices_size, cudaMemcpyHostToDevice));
		h_bvh_indices[i] = mesh.bvh.tri_indices;
		mesh_p->bvh.tri_indices = ref.d_bvh_indices[i];
	}

	Sphere* h_spheres = scene->spheres;
	Plane* h_planes = scene->planes;
	Mesh* h_meshes = scene->meshes;
	MeshInstance* h_instances = scene->instances;
	scene->spheres = ref.d_spheres;
	scene->planes = ref.d_planes;
	scene->meshes = ref.d_meshes;
	scene->instances = ref.d_instances;
	HANDLE_ERROR( cudaMemcpy(ref.d_scene, scene, sizeof(Scene), cudaMemcpyHostToDevice) );
	scene->spheres = h_spheres;
	scene->planes = h_planes;
	scene->meshes = h_meshes;
	scene->instances = h_instances;
	HANDLE_ERROR( cudaMemcpy(ref.d_spheres, scene->spheres, spheres_size, cudaMemcpyHostToDevice) );
	HANDLE_ERROR( cudaMemcpy(ref.d_planes, scene->planes, planes_size, cudaMemcpyHostToDevice) );
	HANDLE_ERROR( cudaMemcpy(ref.d_instances, scene->instances, instances_size, cudaMemcpyHostToDevice) );
	HANDLE_ERROR( cudaMemcpy(ref.d_meshes, scene->meshes, meshes_size, cudaMemcpyHostToDevice) );
	for (int i = 0; i < scene->mesh_amount; i++)
	{
		scene->meshes[i].triangles = h_triangle_pointers[i];
		scene->meshes[i].bvh.nodes = h_bvh_nodes[i];
		scene->meshes[i].bvh.tri_indices = h_bvh_indices[i];
	}
	free(h_triangle_pointers);
	free(h_bvh_nodes);
	free(h_bvh_indices);
	return ref;
}

static void free_scene_gpu(SceneReference ref)
{
	HANDLE_ERROR( cudaFree(ref.d_spheres) );
	HANDLE_ERROR( cudaFree(ref.d_planes) );
	HANDLE_ERROR( cudaFree(ref.d_instances) );
	HANDLE_ERROR( cudaFree(ref.d_meshes) );
	HANDLE_ERROR( cudaFree(ref.d_scene) );
	for (int i = 0; i < ref.mesh_amount; i++)
	{
		HANDLE_ERROR( cudaFree(ref.d_triangle_pointers[i]) );
		HANDLE_ERROR( cudaFree(ref.d_bvh_nodes[i]) );
		HANDLE_ERROR( cudaFree(ref.d_bvh_indices[i]) );
	}
	free(ref.d_triangle_pointers);
	free(ref.d_bvh_nodes);
	free(ref.d_bvh_indices);
}

static void start_timer(cudaEvent_t* start, cudaEvent_t* stop)
{
	HANDLE_ERROR( cudaEventCreate(start) );
	HANDLE_ERROR( cudaEventCreate(stop) );
	HANDLE_ERROR( cudaEventRecord(*start, 0) );
}

static void end_timer(cudaEvent_t* start, cudaEvent_t* stop, float* time)
{
	HANDLE_ERROR( cudaEventRecord(*stop, 0) );
	HANDLE_ERROR( cudaEventSynchronize(*stop) );
	HANDLE_ERROR( cudaEventElapsedTime(time, *start, *stop) );
}
#include "math/aabb.h"

uint32_t wang_hash(uint32_t a)
{
	a = (a ^ 61) ^ (a >> 16);
	a = a + (a << 3);
	a = a ^ (a >> 4);
	a = a * 0x27d4eb2d;
	a = a ^ (a >> 15);
	return a;
}

void render_scene(Scene* scene, Bitmap* bitmap, int samples, int max_depth)
{
	if (!scene)
	{
		return;
	}

	cudaEvent_t render_start;
	cudaEvent_t render_stop;
	start_timer(&render_start, &render_stop);

	HANDLE_ERROR( cudaDeviceSetLimit(cudaLimitMallocHeapSize, 256 * 1024 * 1024) );
	int pixels_amount = bitmap->width * bitmap->height;
	int threads_per_block = 256;
	int blocks_amount = (pixels_amount + threads_per_block - 1) / threads_per_block;

	curandState* d_states;
	HANDLE_ERROR( cudaMalloc(&d_states, sizeof(curandState) * threads_per_block * blocks_amount) );

	RenderInfo* d_info = 
		allocate_render_info_gpu(bitmap->width, bitmap->height, scene->camera);

	Vector3* d_final_colors = allocate_final_colors_gpu(pixels_amount);

	Vector3* d_ray_colors;
	HANDLE_ERROR( cudaMalloc(&d_ray_colors, pixels_amount * sizeof(Vector3)) );

	int* d_ray_statuses;
	HANDLE_ERROR( cudaMalloc(&d_ray_statuses, pixels_amount * sizeof(int)) );

	Ray* d_rays;
	HANDLE_ERROR( cudaMalloc(&d_rays, sizeof(Ray) * pixels_amount) );

	SceneReference ref = allocate_scene_gpu(scene);

	int* h_ray_statuses = (int *) calloc(pixels_amount, sizeof(int));

	printf("Rendering...    "); fflush(stdout);
	int last_progress = -1;
	float progress_step = 100.0f / (float) samples;
	for (int i = 0; i < samples; i++)
	{
		init_curand_states<<<blocks_amount, threads_per_block>>>(d_states, wang_hash(i), pixels_amount);

		init_rays<<<blocks_amount, threads_per_block>>>
			(d_rays, d_ray_statuses, d_ray_colors, d_info, d_states, pixels_amount);

		int active_pixels = pixels_amount;
		int blocks = blocks_amount;

		for (int j = 0; j < max_depth; j++)
		{
			pathtrace_kernel<<<blocks, threads_per_block>>>
				(d_final_colors, d_rays, d_ray_statuses, d_ray_colors, 
				 ref.d_scene, d_states, active_pixels);		
			compact_pixels(d_ray_statuses, h_ray_statuses, &active_pixels);
			blocks = (active_pixels + threads_per_block - 1) / threads_per_block;
		}
		int progress = (int) ((float) i * progress_step);
		if (progress != last_progress)
		{
			printf("\b\b\b%02d%%", progress); fflush(stdout);
			last_progress = progress;
		}
	}
	printf("\b\b\b100%%\n");

	HANDLE_ERROR( cudaFree(d_states) );
	HANDLE_ERROR( cudaFree(d_rays) );
	HANDLE_ERROR( cudaFree(d_info) );
	HANDLE_ERROR( cudaFree(d_ray_statuses) );
	HANDLE_ERROR( cudaFree(d_ray_colors) );
	free_scene_gpu(ref);
	free(h_ray_statuses);

	Pixel* h_pixels = bitmap->pixels;
	Pixel* d_pixels;
	HANDLE_ERROR( cudaMalloc(&d_pixels, sizeof(Pixel) * pixels_amount) );
	HANDLE_ERROR( cudaMemcpy(d_pixels, h_pixels, sizeof(Pixel) * pixels_amount, cudaMemcpyHostToDevice) );

	set_bitmap<<<blocks_amount, threads_per_block>>>(d_final_colors, d_pixels, (float) samples, pixels_amount);
	HANDLE_ERROR( cudaMemcpy(h_pixels, d_pixels, sizeof(Pixel) * pixels_amount, cudaMemcpyDeviceToHost) );

	HANDLE_ERROR( cudaFree(d_final_colors) );
	HANDLE_ERROR( cudaFree(d_pixels) );

	float render_time;
	end_timer(&render_start, &render_stop, &render_time);

	printf("Render time: %f seconds\n", 1e-3 * (double) render_time);
}