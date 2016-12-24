#include "scenebuilder.h"

SceneBuilder* scenebuilder_new()
{
	SceneBuilder* builder = (SceneBuilder *) calloc(1, sizeof(SceneBuilder));
	if (!builder)
	{
		return NULL;
	}
	builder->spheres = arraylist_new(1);
	if (!builder->spheres)
	{
		goto exit;
	}
	builder->planes = arraylist_new(1);
	if (!builder->planes)
	{
		goto exit;
	}
	builder->meshes = arraylist_new(1);
	if (!builder->meshes)
	{
		goto exit;
	}
	builder->instances = arraylist_new(1);
	if (!builder->instances)
	{
		goto exit;
	}
	return builder;
exit:
	scenebuilder_free(builder);
	return NULL;
}

void scenebuilder_free(SceneBuilder* builder)
{
	if (builder)
	{
		for (int i = 0; i < builder->spheres->length; i++)
		{
			sphere_free((Sphere *) arraylist_get(builder->spheres, i));
		}
		for (int i = 0; i < builder->instances->length; i++)
		{
			mesh_instance_free((MeshInstance *) arraylist_get(builder->instances, i));
		}
		for (int i = 0; i < builder->meshes->length; i++)
		{
			Mesh* mesh = (Mesh *) arraylist_get(builder->meshes, i);
			if (mesh)
			{
				free(mesh);
			}
		}

		arraylist_free(builder->spheres);
		arraylist_free(builder->planes);
		arraylist_free(builder->meshes);
		arraylist_free(builder->instances);
		free(builder);
	}
}

void scenebuilder_add_sphere(SceneBuilder* builder, Sphere* sphere)
{
	if (builder && sphere)
	{
		arraylist_add(builder->spheres, sphere);
	}
}

void scenebuilder_add_mesh(SceneBuilder* builder, Mesh* mesh)
{
	if (builder && mesh)
	{
		arraylist_add(builder->meshes, mesh);
	}
}

void scenebuilder_add_mesh_instance(SceneBuilder* builder, MeshInstance* instance)
{
	if (builder && instance)
	{
		arraylist_add(builder->instances, instance);
	}
}