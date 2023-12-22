#include "../CustomRP/ShaderLibrary/Common.hlsl"
#include "../CustomRP/ShaderLibrary/Surface.hlsl"
#include "../CustomRP/ShaderLibrary/Shadows.hlsl"
#include "../CustomRP/ShaderLibrary/GI.hlsl"
#include "../CustomRP/ShaderLibrary/Light.hlsl"
#include "../CustomRP/ShaderLibrary/BRDF.hlsl"
#include "../CustomRP/ShaderLibrary/Lighting.hlsl"

#ifndef CUSTOM_LIT_PASS_INCLUDED
#define CUSTOM_LIT_PASS_INCLUDED

#if defined(LIGHTMAP_ON)
	#define GI_ATTRIBUTE_DATA float2 lightMapUV : TEXCOORD1;
	#define GI_VARYINGS_DATA float2 lightMapUV : VAR_LIGHT_MAP_UV;
	#define TRANSFER_GI_DATA(input, output) \
		output.lightMapUV = input.lightMapUV * \
		unity_LightmapST.xy + unity_LightmapST.zw;
	#define GI_FRAGMENT_DATA(input) input.lightMapUV
#else
	#define GI_ATTRIBUTE_DATA // empty definition means deleted at compile time
	#define GI_VARYINGS_DATA
	#define TRANSFER_GI_DATA(input, output)
	#define GI_FRAGMENT_DATA(input) 0.0
#endif

TEXTURE2D(_BaseMap); // texture handle
SAMPLER(sampler_BaseMap); // controls how texture is sampled (e.g. wrap and filter modes)


//CBUFFER_START(UnityPerMaterial) // required to allow SRP batching; CBUFFER_START and CBUFFER_END are in core RP and equivalent to "cbuffer UnityPerMaterial {float _BaseColor; };" but handles platform incompatibility
//	float4 _BaseColor;
//CBUFFER_END

UNITY_INSTANCING_BUFFER_START(UnityPerMaterial) // equivalent to above but supports GPU instancing
	UNITY_DEFINE_INSTANCED_PROP(float4, _BaseMap_ST) // tiling and offset of texture
	UNITY_DEFINE_INSTANCED_PROP(float4, _BaseColor)
	UNITY_DEFINE_INSTANCED_PROP(float, _Cutoff)
	UNITY_DEFINE_INSTANCED_PROP(float, _Metallic)
	UNITY_DEFINE_INSTANCED_PROP(float, _Smoothness)
UNITY_INSTANCING_BUFFER_END(UnityPerMaterial)

float3 _WorldSpaceCameraPos;

struct Attributes {
	float3 positionOS : POSITION;
	float3 normalOS : NORMAL;
	float2 baseUV : TEXCOORD0;
	GI_ATTRIBUTE_DATA // macro to store light map
	UNITY_VERTEX_INPUT_INSTANCE_ID // contains GPU instancing object index
};

struct Varyings {
	float4 positionCS : SV_POSITION;
	float3 positionWS : VAR_POSITION;
	float3 normalWS : VAR_NORMAL;
	float2 baseUV : VAR_BASE_UV; // can apply any unused identifier as this is just a passed along value (requires no special attention). "VAR_BASE_UV" is arbitrary
	GI_VARYINGS_DATA
	UNITY_VERTEX_INPUT_INSTANCE_ID
};


Varyings LitPassVertex(Attributes input)  {
	Varyings output;
	UNITY_SETUP_INSTANCE_ID(input);
	UNITY_TRANSFER_INSTANCE_ID(input, output);
	TRANSFER_GI_DATA(input, output);
	output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
	output.positionCS = TransformWorldToHClip(output.positionWS);
	output.normalWS = TransformObjectToWorldNormal(input.normalOS);
	float4 baseST = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseMap_ST);
	output.baseUV = input.baseUV * baseST.xy + baseST.zw; // xy contains scale, zw contains offset
	return output;
}

float4 LitPassFragment(Varyings input) : SV_TARGET {
	UNITY_SETUP_INSTANCE_ID(input);
	float4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.baseUV);
	float4 baseColor = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseColor);
	float4 base = baseMap * baseColor;
	#if defined(_CLIPPING)
		clip(base.a - UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Cutoff));
	#endif

	Surface surface;
	surface.position = input.positionWS;
	surface.normal = normalize(input.normalWS);
	surface.color = base.rgb;
	surface.alpha = base.a;
	surface.metallic = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Metallic);
	surface.smoothness =
		UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Smoothness);
	surface.dither = InterleavedGradientNoise(input.positionCS.xy, 0); // InterleavedGradientNoise comes from the Core RP library, and its first param is the screen-space XY position (which = clip space XY position in the fragment shader). Second param is to animate the noise over time (static is zero)
	#if defined(_PREMULTIPLY_ALPHA)
		BRDF brdf = GetBRDF(surface, true);
	#else
		BRDF brdf = GetBRDF(surface);
	#endif
	surface.viewDirection = normalize(_WorldSpaceCameraPos - input.positionWS);
	surface.depth = -TransformWorldToView(input.positionWS).z;
	GI gi = GetGI(GI_FRAGMENT_DATA(input), surface);
	float3 color = GetLighting(surface, brdf, gi);
	return float4(color, surface.alpha);
}

#endif