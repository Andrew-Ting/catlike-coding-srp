#ifndef CUSTOM_UNITY_INPUT_INCLUDED
#define CUSTOM_UNITY_INPUT_INCLUDED

// file containing all values passed down from Unity in the CPU to the GPU
CBUFFER_START(UnityPerDraw)
float4x4 unity_ObjectToWorld;  // set once per draw, remaining constant during that draw
float4x4 unity_WorldToObject;
float4 unity_LODFade; // necessary to make SRP batcher compatible. Otherwise "builtin property offset in cbuffer overlap other stages (UnityPerDraw) is returned"
real4 unity_WorldTransformParams;

float4 unity_LightmapST; // xy is the scale to the light map, zw is the offset in the light map
float4 unity_DynamicLightmapST; // deprecated, only here for SRP compatibility
CBUFFER_END


float4x4 unity_MatrixVP;
float4x4 unity_MatrixV;
float4x4 unity_MatrixInvV;
float4x4 unity_prev_MatrixM;
float4x4 unity_prev_MatrixIM;
float4x4 glstate_matrix_projection;
#endif