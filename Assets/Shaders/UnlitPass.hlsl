#include "../CustomRP/ShaderLibrary/Common.hlsl"

#ifndef CUSTOM_UNLIT_PASS_INCLUDED
#define CUSTOM_UNLIT_PASS_INCLUDED

//CBUFFER_START(UnityPerMaterial) // required to allow SRP batching; CBUFFER_START and CBUFFER_END are in core RP and equivalent to "cbuffer UnityPerMaterial {float _BaseColor; };" but handles platform incompatibility
//	float4 _BaseColor;
//CBUFFER_END

struct Attributes {
	float3 positionOS : POSITION;
	float2 baseUV : TEXCOORD0;
	UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings {
	float4 positionCS : SV_POSITION;
	float2 baseUV : VAR_BASE_UV; // can apply any unused identifier as this is just a passed along value (requires no special attention). "VAR_BASE_UV" is arbitrary
	UNITY_VERTEX_INPUT_INSTANCE_ID
};


Varyings UnlitPassVertex(Attributes input)  {
	Varyings output;
	UNITY_SETUP_INSTANCE_ID(input);
	UNITY_TRANSFER_INSTANCE_ID(input, output);
	float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
	output.positionCS = TransformWorldToHClip(positionWS);
	float4 baseST = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseMap_ST);
	output.baseUV = input.baseUV * baseST.xy + baseST.zw; // xy contains scale, zw contains offset
	return output;
}

float4 UnlitPassFragment(Varyings input) : SV_TARGET {
	UNITY_SETUP_INSTANCE_ID(input);
	float4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.baseUV);
	float4 baseColor = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseColor);
	float4 base = baseMap * baseColor;
	#if defined(_CLIPPING)
		clip(base.a - UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Cutoff));
	#endif
	return base;
}

#endif