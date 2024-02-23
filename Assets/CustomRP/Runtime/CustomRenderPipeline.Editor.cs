using Unity.Collections;
using UnityEngine;
using UnityEngine.Experimental.GlobalIllumination;
using LightType = UnityEngine.LightType; // LightType clashes in UnityEngine and UnityEngine.Experimental.GlobalIllumination

public partial class CustomRenderPipeline
{

    partial void InitializeForEditor();

    #if UNITY_EDITOR
    partial void InitializeForEditor()
    {
        Lightmapping.SetDelegate(lightsDelegate); // tell Unity to overwrite its default lightmapping with our created delegate
    }

    // override the Unity method for disposing pipelines and reset our delegate as well when doing so
    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        Lightmapping.ResetDelegate();
    }

    // override Unity lightmapping functionality by controlling how data from the lights array is transferred to the LightDataGI native array
    static Lightmapping.RequestLightsDelegate lightsDelegate =
            (Light[] lights, NativeArray<LightDataGI> output) => {

                var lightData = new LightDataGI(); // initialize a lightdatagi which Unity will use for the light map
                for (int i = 0; i < lights.Length; i++)
                {
                    Light light = lights[i];
                    switch (light.type)
                    {
                        case LightType.Directional:
                            var directionalLight = new DirectionalLight();
                            LightmapperUtils.Extract(light, ref directionalLight);
                            lightData.Init(ref directionalLight);
                            break;
                        case LightType.Point:
                            var pointLight = new PointLight();
                            LightmapperUtils.Extract(light, ref pointLight);
                            lightData.Init(ref pointLight);
                            break;
                        case LightType.Spot:
                            var spotLight = new SpotLight();
                            LightmapperUtils.Extract(light, ref spotLight);
                            spotLight.innerConeAngle = light.innerSpotAngle * Mathf.Deg2Rad;
                            spotLight.angularFalloff =
                                AngularFalloffType.AnalyticAndInnerAngle;
                            lightData.Init(ref spotLight);
                            break;
                        case LightType.Area:
                            var rectangleLight = new RectangleLight();
                            LightmapperUtils.Extract(light, ref rectangleLight);
                            rectangleLight.mode = LightMode.Baked; // force area light to baked light since realtime is not yet supported
                            lightData.Init(ref rectangleLight);
                            break;
                        default:
                            lightData.InitNoBake(light.GetInstanceID()); // don't bake the light with this instance id if not supported
                            break;
                    }
                    lightData.falloff = FalloffType.InverseSquared; // corrects the Legacy RP's light falloff
                    output[i] = lightData;
                }

            };
    #endif
}