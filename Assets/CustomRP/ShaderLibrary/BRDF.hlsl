#ifndef CUSTOM_BRDF_INCLUDED
#define CUSTOM_BRDF_INCLUDED

struct BRDF {
	float3 diffuse;
	float3 specular;
	float roughness;
	float perceptualRoughness;
	float fresnel;
};

#define MIN_REFLECTIVITY 0.04

float OneMinusReflectivity (float metallic) { // caps the metallicness to 0.96; necessary to make diffuse specular highlights
	float range = 1.0 - MIN_REFLECTIVITY;
	return range - metallic * range;
}

float SpecularStrength (Surface surface, BRDF brdf, Light light) { // Minimalist Cook-Torrance BRDF
	float3 h = SafeNormalize(light.direction + surface.viewDirection);
	float nh2 = Square(saturate(dot(surface.normal, h)));
	float lh2 = Square(saturate(dot(light.direction, h)));
	float r2 = Square(brdf.roughness);
	float d2 = Square(nh2 * (r2 - 1.0) + 1.00001);
	float normalization = brdf.roughness * 4.0 + 2.0;
	return r2 / (d2 * max(0.1, lh2) * normalization);
}

float3 DirectBRDF (Surface surface, BRDF brdf, Light light) {
	return SpecularStrength(surface, brdf, light) * brdf.specular + brdf.diffuse;
}

float3 IndirectBRDF (
	Surface surface, BRDF brdf, float3 diffuse, float3 specular
) {
	float fresnelStrength = surface.fresnelStrength *
		Pow4(1.0 - saturate(dot(surface.normal, surface.viewDirection)));
	float3 reflection = specular * lerp(brdf.specular, brdf.fresnel, fresnelStrength);
	reflection /= brdf.roughness * brdf.roughness + 1.0; // low roughness doesn't affect reflection but max roughness halves reflection

	 // multiply baked indirect lighting color computation (GI) with realtime computed diffuse reflectivity from brdf, then add reflecions 
	 // finally modulate this with texture read occlusion to darken indirect light in tight spaces and produce final fragment color (by indirect light; direct light is not influenced by occlusion data as tight spaces are still lit when hit by light directly)
    return (diffuse * brdf.diffuse + reflection) * surface.occlusion;
}

BRDF GetBRDF (Surface surface, bool applyAlphaToDiffuse = false) {
	BRDF brdf;
	float oneMinusReflectivity = OneMinusReflectivity (surface.metallic);
	brdf.diffuse = surface.color * oneMinusReflectivity;
	if (applyAlphaToDiffuse) {
		brdf.diffuse *= surface.alpha; // premultiplied alpha blending
	}
	brdf.specular =  lerp(MIN_REFLECTIVITY, surface.color, surface.metallic);
	brdf.perceptualRoughness =
		PerceptualSmoothnessToPerceptualRoughness(surface.smoothness);
	brdf.roughness = PerceptualRoughnessToRoughness(brdf.perceptualRoughness);
	brdf.fresnel = saturate(surface.smoothness + 1.0 - oneMinusReflectivity); // fresnel is strong when the surface is smooth or very metallic or both; Shlick approximation
	return brdf;
}
#endif