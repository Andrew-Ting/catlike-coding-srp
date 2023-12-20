#ifndef CUSTOM_SHADOWS_INCLUDED
#define CUSTOM_SHADOWS_INCLUDED

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Shadow/ShadowSamplingTent.hlsl" // core RP library containing functions for percentage closer filtering

#if defined(_DIRECTIONAL_PCF3)
	#define DIRECTIONAL_FILTER_SAMPLES 4
	#define DIRECTIONAL_FILTER_SETUP SampleShadow_ComputeSamples_Tent_3x3
#elif defined(_DIRECTIONAL_PCF5)
	#define DIRECTIONAL_FILTER_SAMPLES 9
	#define DIRECTIONAL_FILTER_SETUP SampleShadow_ComputeSamples_Tent_5x5
#elif defined(_DIRECTIONAL_PCF7)
	#define DIRECTIONAL_FILTER_SAMPLES 16
	#define DIRECTIONAL_FILTER_SETUP SampleShadow_ComputeSamples_Tent_7x7
#endif

#define MAX_SHADOWED_DIRECTIONAL_LIGHT_COUNT 4
#define MAX_CASCADE_COUNT 4
#define SHADOW_SAMPLER sampler_linear_clamp_compare

TEXTURE2D_SHADOW(_DirectionalShadowAtlas); // texture2d_shadow explicitly says it is a shadow (vs texture2d), though makes no difference logically
// SAMPLER_CMP(sampler_DirectionalShadowAtlas); // actually different from SAMPLER, since SAMPLER's regular bilinear filter sampling is bad for depth data

SAMPLER_CMP(SHADOW_SAMPLER); 

CBUFFER_START(_CustomShadows)
	int _CascadeCount;
	float4 _CascadeCullingSpheres[MAX_CASCADE_COUNT];
	float4 _CascadeData[MAX_CASCADE_COUNT];
	float4x4 _DirectionalShadowMatrices[MAX_SHADOWED_DIRECTIONAL_LIGHT_COUNT * MAX_CASCADE_COUNT];
	float4 _ShadowAtlasSize;
	float4 _ShadowDistanceFade;
CBUFFER_END

struct DirectionalShadowData { // per light
	float strength;
	int tileIndex;
	float normalBias;
};

struct ShadowData { // per fragment
	int cascadeIndex;
	float cascadeBlend; // blend across cascades
	float strength;
};

float FadedShadowStrength (float distance, float scale, float fade) { // fade between different shadow cascades
	return saturate((1.0 - distance * scale) * fade);
}

ShadowData GetShadowData (Surface surfaceWS) {
	ShadowData data;
	data.cascadeBlend = 1.0;
	data.strength = FadedShadowStrength(
		surfaceWS.depth, _ShadowDistanceFade.x, _ShadowDistanceFade.y
	);
	// surfaceWS.depth < _ShadowDistance ? 1.0 : 0.0;
	int i;
	for (i = 0; i < _CascadeCount; i++) {
		float4 sphere = _CascadeCullingSpheres[i];
		float distanceSqr = DistanceSquared(surfaceWS.position, sphere.xyz);
		if (distanceSqr < sphere.w) { // find the smallest culling sphere which contains the given fragment and use that cascade map resolution
			float fade = FadedShadowStrength(
					distanceSqr, _CascadeData[i].x * _CascadeData[i].x, _ShadowDistanceFade.z
				);
			if (i == _CascadeCount - 1) {
				data.strength *= fade; // shadows fade out at the last cascade
			}
			else {
				data.cascadeBlend = fade; // shadows blend to the next cascade for all but the last cascade
			}
			break;
		}
	}

	if (i == _CascadeCount) {
		data.strength = 0.0; // cull all shadows beyond last cascade
	}
	#if defined(_CASCADE_BLEND_DITHER)
		else if (data.cascadeBlend < surfaceWS.dither) { // move forward one cascade if the dither noise for the fragment is > its cascade blend value (which shrinks as you approach next cascade); effectively increases sampling of the next cascade as you approach it 
			i += 1;
		}
	#endif
	#if !defined(_CASCADE_BLEND_SOFT)
		data.cascadeBlend = 1.0; // cascade blend only matters for soft blending; can eliminate the cascadeblend setting above at compile time for non-soft blend variants
	#endif
	data.cascadeIndex = i;
	return data;
}

float SampleDirectionalShadowAtlas (float3 positionSTS) {
	return SAMPLE_TEXTURE2D_SHADOW(
		_DirectionalShadowAtlas, SHADOW_SAMPLER, positionSTS
	);
}

float FilterDirectionalShadow (float3 positionSTS) {
	#if defined(DIRECTIONAL_FILTER_SETUP)
		float weights[DIRECTIONAL_FILTER_SAMPLES];
		float2 positions[DIRECTIONAL_FILTER_SAMPLES];
		float4 size = _ShadowAtlasSize.yyxx; 
		DIRECTIONAL_FILTER_SETUP(size, positionSTS.xy, weights, positions);
		float shadow = 0;
		for (int i = 0; i < DIRECTIONAL_FILTER_SAMPLES; i++) { // compute the resulting shadow color of a tent filter kernel weighting of shadow map
			shadow += weights[i] * SampleDirectionalShadowAtlas(
				float3(positions[i].xy, positionSTS.z)
			);
		}
		return shadow;
	#else
		return SampleDirectionalShadowAtlas(positionSTS);
	#endif
}

float GetDirectionalShadowAttenuation (DirectionalShadowData directional, ShadowData global, Surface surfaceWS) { // sample the right position of the shadow map
	#if !defined(_RECEIVE_SHADOWS)
		return 1.0;
	#endif
	
	if (directional.strength <= 0.0) { // lerp extrapolates, so we need to return clamped value 1 when strength is < 0
		return 1.0;
	}
	float3 normalBias = surfaceWS.normal * (directional.normalBias * _CascadeData[global.cascadeIndex].y); // increase normal by texel size to remove some shadow acne
	float3 positionSTS = mul(
		_DirectionalShadowMatrices[directional.tileIndex],
		float4(surfaceWS.position + normalBias, 1.0)
	).xyz;
	float shadow = FilterDirectionalShadow(positionSTS);
	if (global.cascadeBlend < 1.0) { // we should sample onto the next cascade and blend it to the current cascade if cascadeblend < 1
		normalBias = surfaceWS.normal *
			(directional.normalBias * _CascadeData[global.cascadeIndex + 1].y);
		positionSTS = mul(
			_DirectionalShadowMatrices[directional.tileIndex + 1],
			float4(surfaceWS.position + normalBias, 1.0)
		).xyz;
		shadow = lerp(
			FilterDirectionalShadow(positionSTS), shadow, global.cascadeBlend
		);
	}
	return lerp(1.0, shadow, directional.strength);
}

#endif