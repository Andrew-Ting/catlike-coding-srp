#include "../CustomRP/ShaderLibrary/Surface.hlsl"
#include "../CustomRP/ShaderLibrary/Shadows.hlsl"
#include "../CustomRP/ShaderLibrary/Light.hlsl"
#include "../CustomRP/ShaderLibrary/BRDF.hlsl"
#include "../CustomRP/ShaderLibrary/GI.hlsl"
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



//CBUFFER_START(UnityPerMaterial) // required to allow SRP batching; CBUFFER_START and CBUFFER_END are in core RP and equivalent to "cbuffer UnityPerMaterial {float _BaseColor; };" but handles platform incompatibility
//	float4 _BaseColor;
//CBUFFER_END

float3 _WorldSpaceCameraPos;

struct Attributes {
	float3 positionOS : POSITION;
	float3 normalOS : NORMAL;
	float4 tangentOS : TANGENT;
	float2 baseUV : TEXCOORD0;
	GI_ATTRIBUTE_DATA // macro to store light map
	UNITY_VERTEX_INPUT_INSTANCE_ID // contains GPU instancing object index
};

struct Varyings {
	float4 positionCS : SV_POSITION;
	float3 positionWS : VAR_POSITION;
	float3 normalWS : VAR_NORMAL;
	float4 tangentWS : VAR_TANGENT;
	float2 baseUV : VAR_BASE_UV; // can apply any unused identifier as this is just a passed along value (requires no special attention). "VAR_BASE_UV" is arbitrary
	float2 detailUV : VAR_DETAIL_UV;
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
	output.tangentWS =
		float4(TransformObjectToWorldDir(input.tangentOS.xyz), input.tangentOS.w);
	float4 baseST = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseMap_ST);
	output.baseUV = TransformBaseUV(input.baseUV); 
	output.detailUV = TransformDetailUV(input.baseUV);
	return output;
}

float4 LitPassFragment(Varyings input) : SV_TARGET {
	UNITY_SETUP_INSTANCE_ID(input);
	ClipLOD(input.positionCS.xy, unity_LODFade.x);
	float4 base = GetBase(input.baseUV, input.detailUV);
	#if defined(_CLIPPING)
		clip(base.a - GetCutoff(input.baseUV));
	#endif

	Surface surface;
	surface.position = input.positionWS;
	surface.normal = NormalTangentToWorld(
		GetNormalTS(input.baseUV, input.detailUV), input.normalWS, input.tangentWS
	);
	surface.interpolatedNormal = input.normalWS;
	surface.color = base.rgb;
	surface.alpha = base.a;
	surface.metallic = GetMetallic(input.baseUV);
	surface.occlusion = GetOcclusion(input.baseUV);
	surface.smoothness = GetSmoothness(input.baseUV, input.detailUV);
	surface.fresnelStrength = GetFresnel(input.baseUV);
	surface.dither = InterleavedGradientNoise(input.positionCS.xy, 0); // InterleavedGradientNoise comes from the Core RP library, and its first param is the screen-space XY position (which = clip space XY position in the fragment shader). Second param is to animate the noise over time (static is zero)
	#if defined(_PREMULTIPLY_ALPHA)
		BRDF brdf = GetBRDF(surface, true);
	#else
		BRDF brdf = GetBRDF(surface);
	#endif
	surface.viewDirection = normalize(_WorldSpaceCameraPos - input.positionWS);
	surface.depth = -TransformWorldToView(input.positionWS).z;
	GI gi = GetGI(GI_FRAGMENT_DATA(input), surface, brdf);
	float3 color = GetLighting(surface, brdf, gi);
	color += GetEmission(input.baseUV);
	return float4(color, surface.alpha);
}

#endif