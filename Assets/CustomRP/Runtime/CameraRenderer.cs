using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Profiling;

public partial class CameraRenderer
{

    ScriptableRenderContext context;
    Camera camera;

    const string bufferName = "Render Camera";
    CommandBuffer buffer = new CommandBuffer
    {
        name = bufferName
    }; // object initializer syntax. Equivalent to new CommandBuffer() passing the parameters in curly braces

    CullingResults cullingResults; // stores what is visible on the camera

    static ShaderTagId unlitShaderTagId = new ShaderTagId("SRPDefaultUnlit"); // fetch the chosen pass to indicate it is allowed in this RP
	static ShaderTagId litShaderTagId = new ShaderTagId("CustomLit");
    Lighting lighting = new Lighting();
    public void Render(ScriptableRenderContext context, Camera camera, bool useDynamicBatching, bool useGPUInstancing, ShadowSettings shadowSettings)
    {
        this.context = context;
        this.camera = camera;

        PrepareBuffer();
        PrepareForSceneWindow();
        if (!Cull(shadowSettings.maxDistance)) {
            return;
        }
        buffer.BeginSample(SampleName);
        ExecuteBuffer();
        lighting.Setup(context, cullingResults, shadowSettings);
        buffer.EndSample(SampleName);
        Setup();
        DrawVisibleGeometry(useDynamicBatching, useGPUInstancing);
        DrawUnsupportedShaders();
        DrawGizmos();
        lighting.Cleanup();
        Submit();
    }

    void Setup()
    {
        context.SetupCameraProperties(camera); // sets up view and projection matrix of camera
        CameraClearFlags flags = camera.clearFlags;
        buffer.ClearRenderTarget(flags <= CameraClearFlags.Depth, flags <= CameraClearFlags.Color, flags == CameraClearFlags.Color ? camera.backgroundColor.linear : Color.clear); // automatically wraps clearing in the command buffer's name, which is redundant to and hence before BeginSample
        buffer.BeginSample(SampleName); // tell frame debugger to begin profiling this buffer from here. Ended with buffer.EndSample with the same buffername passed in
        ExecuteBuffer();
    }

    void DrawVisibleGeometry(bool useDynamicBatching, bool useGPUInstancing)
    {
        // context draw commands are put on a queue to be rendered. We only render them by calling context.Submit()
        var sortingSettings = new SortingSettings(camera) {
            criteria = SortingCriteria.CommonOpaque // determines in what order objects are drawn in frame rendering
        
        }; // determines if we do orthographic or distance-based sorting
        var drawingSettings = new DrawingSettings(unlitShaderTagId, sortingSettings)
        {
            enableDynamicBatching = useDynamicBatching,
            enableInstancing = useGPUInstancing,
            perObjectData = PerObjectData.Lightmaps // instructs the pipeline to send UV coords for light maps to the shaders; lightmapped objects have the LIGHTMAP_ON keyword in their shader variant
        };
        drawingSettings.SetShaderPassName(1, litShaderTagId);
        var filteringSettings = new FilteringSettings(RenderQueueRange.opaque); // indicate which render queues are rendered in the next drawrenderers call

        context.DrawRenderers(
            cullingResults, ref drawingSettings, ref filteringSettings
        );
        
        context.DrawSkybox(camera);

        sortingSettings.criteria = SortingCriteria.CommonTransparent;
        drawingSettings.sortingSettings = sortingSettings;
        filteringSettings.renderQueueRange = RenderQueueRange.transparent;

        context.DrawRenderers(
            cullingResults, ref drawingSettings, ref filteringSettings
        );

    }

    void Submit()
    {
        buffer.EndSample(SampleName);
        ExecuteBuffer();
        context.Submit();
    }

    void ExecuteBuffer()
    { // executing a buffer and clearing it always comes together
        context.ExecuteCommandBuffer(buffer); // copies commands from buffer into context
        buffer.Clear();
    }

    bool Cull(float maxShadowDistance)
    {
        if (camera.TryGetCullingParameters(out ScriptableCullingParameters p)) // returns true if culling parameters can be obtained, and the "out" syntax puts the parameters into the p variable 
        {
            p.shadowDistance = Mathf.Min(maxShadowDistance, camera.farClipPlane); // shadow distance is set by the culling parameters
            cullingResults = context.Cull(ref p); // "ref" passes parameter by reference
            return true;
        }
        return false;
    }

}
