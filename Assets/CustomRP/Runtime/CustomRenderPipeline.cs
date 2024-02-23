using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

public partial class CustomRenderPipeline : RenderPipeline
{
    CameraRenderer renderer = new CameraRenderer();
    bool useDynamicBatching, useGPUInstancing;
    ShadowSettings shadowSettings;
    public CustomRenderPipeline(bool useDynamicBatching, bool useGPUInstancing, bool useSRPBatcher, ShadowSettings shadowSettings)
    {
        this.useGPUInstancing = useGPUInstancing;
        this.useDynamicBatching = useDynamicBatching;
        this.shadowSettings = shadowSettings;
        GraphicsSettings.useScriptableRenderPipelineBatching = false;
        GraphicsSettings.lightsUseLinearIntensity = true;
        InitializeForEditor();
    }
    // legacy, but still required as Unity defines the abstract class of this
    protected override void Render(
        ScriptableRenderContext context, Camera[] cameras
    )
    { }

    protected override void Render(
        ScriptableRenderContext context, List<Camera> cameras
    ) // context is a connection to the native engine, camera array represents the multiple cameras in the scene to render
    { 
        for (int i = 0; i < cameras.Count; i++)
        {
            renderer.Render(context, cameras[i], useDynamicBatching, useGPUInstancing, shadowSettings);
        }
    
    }
}
