#ifndef CUSTOM_UNITY_INPUT_INCLUDED
#define CUSTOM_UNITY_INPUT_INCLUDED

// file containing all values passed down from Unity in the CPU to the GPU
CBUFFER_START(UnityPerDraw)
float4x4 unity_ObjectToWorld;  // set once per draw, remaining constant during that draw
float4x4 unity_WorldToObject;
float4 unity_LODFade; // necessary to make SRP batcher compatible. Otherwise "builtin property offset in cbuffer overlap other stages (UnityPerDraw)" is returned; stores the fade value of LOD groups
real4 unity_WorldTransformParams;

float4 unity_ProbesOcclusion; // contains the shadow mask data interpolated across light probes, which Unity calls "occlusion probes"

float4 unity_LightmapST; // xy is the scale to the light map, zw is the offset in the light map
float4 unity_DynamicLightmapST; // deprecated, only here for SRP compatibility

// the 7 light probe lighting approximation polynomial coefficients
float4 unity_SHAr;
float4 unity_SHAg;
float4 unity_SHAb;
float4 unity_SHBr;
float4 unity_SHBg;
float4 unity_SHBb;
float4 unity_SHC;

// the 4 light probe proxy volume variables
float4 unity_ProbeVolumeParams;
float4x4 unity_ProbeVolumeWorldToObject;
float4 unity_ProbeVolumeSizeInv;
float4 unity_ProbeVolumeMin;
CBUFFER_END


float4x4 unity_MatrixVP;
float4x4 unity_MatrixV;
float4x4 unity_MatrixInvV;
float4x4 unity_prev_MatrixM;
float4x4 unity_prev_MatrixIM;
float4x4 glstate_matrix_projection;
#endif