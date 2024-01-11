#ifndef CUSTOM_INPUT_CONFIG_INCLUDED
#define CUSTOM_INPUT_CONFIG_INCLUDED

struct InputConfig {
	float2 baseUV;
	float2 detailUV;
	bool useMask;
	bool useDetail;
};

InputConfig GetInputConfig (float2 baseUV, float2 detailUV = 0.0) {
	InputConfig c;
	c.baseUV = baseUV;
	c.detailUV = detailUV;
	c.useMask = false;
	c.useDetail = false;
	return c;
}
#endif