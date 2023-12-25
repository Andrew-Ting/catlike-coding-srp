#ifndef CUSTOM_META_PASS_INCLUDED
#define CUSTOM_META_PASS_INCLUDED

#include "../CustomRP/ShaderLibrary/Surface.hlsl"
#include "../CustomRP/ShaderLibrary/Shadows.hlsl"
#include "../CustomRP/ShaderLibrary/Light.hlsl"
#include "../CustomRP/ShaderLibrary/BRDF.hlsl"

bool4 unity_MetaFragmentControl;
float unity_OneOverOutputBoost;
float unity_MaxOutputValue;

struct Attributes {
	float3 positionOS : POSITION;
	float2 baseUV : TEXCOORD0;
	float2 lightMapUV : TEXCOORD1;
};

struct Varyings {
	float4 positionCS : SV_POSITION;
	float2 baseUV : VAR_BASE_UV;
};

Varyings MetaPassVertex (Attributes input) {
	input.positionOS.xy =
		input.lightMapUV * unity_LightmapST.xy + unity_LightmapST.zw; // meta pass expects positionOS to be the lightmap uv coordinates
	input.positionOS.z = input.positionOS.z > 0.0 ? FLT_MIN : 0.0; // z value is not important for a 2d lightmap texture; assign a dummy value the same way Unity does (but still required as OpenGL doesn't work without explicitly using z-coord)
	Varyings output;
	output.positionCS = TransformWorldToHClip(input.positionOS); // meta pass expects fragment shader positionCS to be lightmap uv coords converted into clipping space
	output.baseUV = TransformBaseUV(input.baseUV);
	return output;
}

float4 MetaPassFragment (Varyings input) : SV_TARGET {
	float4 base = GetBase(input.baseUV);
	Surface surface;
	ZERO_INITIALIZE(Surface, surface);
	surface.color = base.rgb;
	surface.metallic = GetMetallic(input.baseUV);
	surface.smoothness = GetSmoothness(input.baseUV);
	BRDF brdf = GetBRDF(surface);
	float4 meta = 0.0;
	if (unity_MetaFragmentControl.x) {
		meta = float4(brdf.diffuse, 1.0);
	}
	else if (unity_MetaFragmentControl.y) {
		meta = float4(GetEmission(input.baseUV), 1.0);
	}
	meta.rgb += brdf.specular * brdf.roughness * 0.5; // boost reflected light results; highly specular but rough materials also pass indirect light
	meta.rgb = min(
			PositivePow(meta.rgb, unity_OneOverOutputBoost), unity_MaxOutputValue
	); // boosts results further until a cap value; "unity_OneOverOutputBoost" and "unity_MaxOutputValue" are provided in the meta pass as floats
	return meta;
}

#endif