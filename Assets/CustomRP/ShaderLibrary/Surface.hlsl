#ifndef CUSTOM_SURFACE_INCLUDED
#define CUSTOM_SURFACE_INCLUDED

struct Surface {
	float3 normal; // normal of the surface considering normal maps
	float3 interpolatedNormal; // normal of the surface ignoring normal maps (used for shadow bias)
	float3 viewDirection;
	float3 color;
	float alpha;
	float metallic;
	float occlusion;
	float smoothness;
	float fresnelStrength;
	float3 position;
	float depth;
	float dither;
};

#endif