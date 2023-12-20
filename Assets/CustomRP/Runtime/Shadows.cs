using UnityEngine;
using UnityEngine.Rendering;

public class Shadows
{
    const int maxShadowedDirectionalLightCount = 4, maxCascades = 4;

    const string bufferName = "Shadows";

    CommandBuffer buffer = new CommandBuffer
    {
        name = bufferName
    };
    struct ShadowedDirectionalLight
    {
        public int visibleLightIndex;
        public float slopeScaleBias;
        public float nearPlaneOffset;
    }

    struct DirectionalShadowData
    {
        float strength;
        int tileIndex;
        float normalBias;
    };

    ShadowedDirectionalLight[] ShadowedDirectionalLights =
        new ShadowedDirectionalLight[maxShadowedDirectionalLightCount];

    ScriptableRenderContext context;

    CullingResults cullingResults;

    ShadowSettings settings;

    int ShadowedDirectionalLightCount;
    static int dirShadowAtlasId = Shader.PropertyToID("_DirectionalShadowAtlas"),
        dirShadowMatricesId = Shader.PropertyToID("_DirectionalShadowMatrices"),
        cascadeCountId = Shader.PropertyToID("_CascadeCount"),
        cascadeCullingSpheresId = Shader.PropertyToID("_CascadeCullingSpheres"),
        cascadeDataId = Shader.PropertyToID("_CascadeData"),
        shadowAtlasSizeId = Shader.PropertyToID("_ShadowAtlasSize"),
        shadowDistanceFadeId = Shader.PropertyToID("_ShadowDistanceFade");

    static Vector4[] cascadeCullingSpheres = new Vector4[maxCascades], 
        cascadeData = new Vector4[maxCascades];

    static Matrix4x4[]
        dirShadowMatrices = new Matrix4x4[maxShadowedDirectionalLightCount * maxCascades];

    static string[] directionalFilterKeywords = {
        "_DIRECTIONAL_PCF3",
        "_DIRECTIONAL_PCF5",
        "_DIRECTIONAL_PCF7",
    };

    static string[] cascadeBlendKeywords = {
        "_CASCADE_BLEND_SOFT",
        "_CASCADE_BLEND_DITHER"
    };
    public void Setup(
        ScriptableRenderContext context, CullingResults cullingResults,
        ShadowSettings settings
    )
    {
        this.context = context;
        this.cullingResults = cullingResults;
        this.settings = settings;
        ShadowedDirectionalLightCount = 0;
    }

    void SetKeywords(string[] keywords, int enabledIndex) {
        for (int i = 0; i < keywords.Length; i++)
        {
            if (i == enabledIndex)
            {
                buffer.EnableShaderKeyword(keywords[i]);
            }
            else
            {
                buffer.DisableShaderKeyword(keywords[i]);
            }
        }
    }

    Vector2 SetTileViewport(int index, int split, float tileSize)
    {
        Vector2 offset = new Vector2(index % split, index / split); // determine which section of the texture the light will write depths to
        buffer.SetViewport(new Rect( // set the buffer to only write on a certain part of the texture/camera view
            offset.x * tileSize, offset.y * tileSize, tileSize, tileSize
        )); // x offset, y offset, width of write, height of write
        return offset;
    }

    Matrix4x4 ConvertToAtlasMatrix(Matrix4x4 m, Vector2 offset, int split)
    {
        if (SystemInfo.usesReversedZBuffer)
        {
            m.m20 = -m.m20;
            m.m21 = -m.m21;
            m.m22 = -m.m22;
            m.m23 = -m.m23;
        }
        // convert clip space to NDCS, multiplies 4x4 matrix
        // [0.5, 0, 0, 0.5]
        // [0, 0.5, 0, 0.5]
        // [0, 0, 0.5, 0.5]
        // [0, 0,   0,   1]
        // to the view * projection matrix
        // then to consider that the textures have width/height 0 to 1/split in the shadow map, we scale further by 1/split and fix the x/y coord offset accordingly
        // we don't need to change the z offset since it does not affect the sampled (x,y) shadow map texture
        float scale = 1f / split;
        m.m00 = (0.5f * (m.m00 + m.m30) + offset.x * m.m30) * scale;
        m.m01 = (0.5f * (m.m01 + m.m31) + offset.x * m.m31) * scale;
        m.m02 = (0.5f * (m.m02 + m.m32) + offset.x * m.m32) * scale;
        m.m03 = (0.5f * (m.m03 + m.m33) + offset.x * m.m33) * scale;
        m.m10 = (0.5f * (m.m10 + m.m30) + offset.y * m.m30) * scale;
        m.m11 = (0.5f * (m.m11 + m.m31) + offset.y * m.m31) * scale;
        m.m12 = (0.5f * (m.m12 + m.m32) + offset.y * m.m32) * scale;
        m.m13 = (0.5f * (m.m13 + m.m33) + offset.y * m.m33) * scale;
        m.m20 = 0.5f * (m.m20 + m.m30);
        m.m21 = 0.5f * (m.m21 + m.m31);
        m.m22 = 0.5f * (m.m22 + m.m32);
        m.m23 = 0.5f * (m.m23 + m.m33);

        return m;
    }

    public void Render()
    {
        if (ShadowedDirectionalLightCount > 0)
        {
            RenderDirectionalShadows();
        }
        else
        {
            buffer.GetTemporaryRT(
                dirShadowAtlasId, 1, 1,
                32, FilterMode.Bilinear, RenderTextureFormat.Shadowmap
            );
        }
    }

    void RenderDirectionalShadows() {

        SetKeywords(directionalFilterKeywords, (int)settings.directional.filter - 1); // sets the filter for the shadow map
        SetKeywords(cascadeBlendKeywords, (int)settings.directional.cascadeBlend - 1); // sets the filter for the shadow map

        int atlasSize = (int)settings.directional.atlasSize;
        int tiles = ShadowedDirectionalLightCount * settings.directional.cascadeCount;
		int split = tiles <= 1 ? 1 : tiles <= 4 ? 2 : 4;
        int tileSize = atlasSize / split;

        buffer.GetTemporaryRT(dirShadowAtlasId, atlasSize, atlasSize,
            32, FilterMode.Bilinear, RenderTextureFormat.Shadowmap); // claim an atlassize x atlassize texture with 32 bit depth buffer, bilinear filtering, and declares it as a shadow map
        buffer.SetRenderTarget(
               dirShadowAtlasId,
               RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store
           );
        buffer.ClearRenderTarget(true, false, Color.clear);
        buffer.BeginSample(bufferName);
        ExecuteBuffer();
        for (int i = 0; i < ShadowedDirectionalLightCount; i++)
        {
            RenderDirectionalShadows(i, split, tileSize);
        }
        buffer.SetGlobalInt(cascadeCountId, settings.directional.cascadeCount);
        buffer.SetGlobalVectorArray(
            cascadeCullingSpheresId, cascadeCullingSpheres
        );
        buffer.SetGlobalVectorArray(cascadeDataId, cascadeData);
        buffer.SetGlobalMatrixArray(dirShadowMatricesId, dirShadowMatrices);
        float f = 1f - settings.directional.cascadeFade;
        buffer.SetGlobalVector(
            shadowDistanceFadeId,
            new Vector4(1f / settings.maxDistance, 1f / settings.distanceFade, 1f / (1f - f * f))
        );
        buffer.SetGlobalVector(
            shadowAtlasSizeId, new Vector4(atlasSize, 1f / atlasSize) // shadow map resolution and size of texel relative to atlas
        );
        buffer.EndSample(bufferName);
        ExecuteBuffer(); // execute reading the shadow map to determine in-game shadows
    }

    void RenderDirectionalShadows(int index, int split, int tileSize) {
        ShadowedDirectionalLight light = ShadowedDirectionalLights[index];
        var shadowSettings =
            new ShadowDrawingSettings(cullingResults, light.visibleLightIndex,
            BatchCullingProjectionType.Orthographic);
        int cascadeCount = settings.directional.cascadeCount;
        int tileOffset = index * cascadeCount;
        Vector3 ratios = settings.directional.CascadeRatios;
        float cullingFactor =
            Mathf.Max(0f, 0.8f - settings.directional.cascadeFade); // cull factor of 1 is already conservative, but play safe. As cascade fade increases, cull less to make sure Unity doesn't accidentally cull shadows in the transition region
        for (int i = 0; i < cascadeCount; i++)
        {
            cullingResults.ComputeDirectionalShadowMatricesAndCullingPrimitives(
                light.visibleLightIndex, i, cascadeCount, ratios, tileSize, light.nearPlaneOffset,
                out Matrix4x4 viewMatrix, out Matrix4x4 projectionMatrix,
                out ShadowSplitData splitData
            ); // gives the clip space cube overlapping area visible to camera and containing light shadows (in splitData), the cascade culling spheres (also in splitData), as well as the view and projection matrix of the light
            // 2nd arg is cascade number, 3rd arg is total # of cascades, 4th arg is an array of length *3rd arg* determining resolution of each cascade (0 is lowest res, 1 is highest res), 5th arg is size of shadow map, 6th arg is near plane of the light's shadow map

            splitData.shadowCascadeBlendCullingFactor = cullingFactor; // tries to cull shadow casters from larger cascades when it's guaranteed the culled section is visible in a smaller cascade

            shadowSettings.splitData = splitData; // pass information about shadow culling to shadow settings
            if (index == 0) // only need to set the culling spheres using the first light, since all other lights use the same cullilng spheres
            {
                SetCascadeData(i, splitData.cullingSphere, tileSize);
            }
            int tileIndex = tileOffset + i;
            dirShadowMatrices[tileIndex] = ConvertToAtlasMatrix(
                projectionMatrix * viewMatrix,
                SetTileViewport(tileIndex, split, tileSize), split
            );
            buffer.SetViewProjectionMatrices(viewMatrix, projectionMatrix); // set matrices for this buffer as calculated by the ComputeDirectionalShadowMatricesAndCullingPrimitives function
            //buffer.SetGlobalDepthBias(500000f, 0f); hack to improve shadow acne, but causes peter panning
            buffer.SetGlobalDepthBias(0f, light.slopeScaleBias);
            ExecuteBuffer(); // execute render shadow map
            context.DrawShadows(ref shadowSettings);
            //buffer.SetGlobalDepthBias(0f, 0f);
            buffer.SetGlobalDepthBias(0f, 0f);
        }
    }

    void SetCascadeData(int index, Vector4 cullingSphere, float tileSize)
    {
        float texelSize = 2f * cullingSphere.w / tileSize; // texture pixel size on one dimension is the diameter of the sphere / specified tile size
        float filterSize = texelSize * ((float)settings.directional.filter + 1f); // scale the texel offset to the PCF filter size; = texel size for the default 2x2 bilinear filter
        cascadeData[index] = new Vector4(
            1f / cullingSphere.w, // inverse of squared cascade radius
            filterSize * 1.4142136f // to guarantee we sample a different texel, we multiply by sqrt(2) since the worst case is an offset along the texel diagonal
        );
        cullingSphere.w -= filterSize; // reduce culling sphere size to prevent sampling beyond the shadow map bounds with the filterSize
        cullingSphere.w *= cullingSphere.w; // compute squared radius of culling spheres to prevent sqrt calculations
        cascadeCullingSpheres[index] = cullingSphere;
    }

    public Vector3 ReserveDirectionalShadows(Light light, int visibleLightIndex) { // reserves space in the shadow atlas for the light shadow map and store information to render it
        if (ShadowedDirectionalLightCount < maxShadowedDirectionalLightCount &&
            light.shadows != LightShadows.None && light.shadowStrength > 0f &&
            cullingResults.GetShadowCasterBounds(visibleLightIndex, out Bounds b)) // don't render shadows for cameras where strength is 0 or shadow set to "None," or if we hit shadow limit, or if the light only affects objects beyond max shadow distance (GetShadowCasterBounds)
        { // GetShadowCasterBounds returns true when the bounds are valid. It is invalid when there are no shadows to render for the light
            ShadowedDirectionalLights[ShadowedDirectionalLightCount] =
                new ShadowedDirectionalLight
                {
                    visibleLightIndex = visibleLightIndex,
                    slopeScaleBias = light.shadowBias,
                    nearPlaneOffset = light.shadowNearPlane
                };
            return new Vector3(
                light.shadowStrength, settings.directional.cascadeCount * ShadowedDirectionalLightCount++,
                light.shadowNormalBias
            );
        }
        return Vector3.zero;
    }

    public void Cleanup()
    {
        buffer.ReleaseTemporaryRT(dirShadowAtlasId);
        ExecuteBuffer();
    }

    void ExecuteBuffer()
    {
        context.ExecuteCommandBuffer(buffer);
        buffer.Clear();
    }
}