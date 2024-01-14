using UnityEditor;
using UnityEngine;

[CanEditMultipleObjects]
[CustomEditorForRenderPipeline(typeof(Light), typeof(CustomRenderPipelineAsset))]
public class CustomLight : LightEditor
{
    public override void OnInspectorGUI()
    {
        base.OnInspectorGUI();
        if (
            !settings.lightType.hasMultipleDifferentValues &&
            (LightType)settings.lightType.enumValueIndex == LightType.Spot
        ) // if the lights we have selected are all the same type && one of them is a spot light:
        {
            settings.DrawInnerAndOuterSpotAngle(); // add inner and outer spot angle widget (built in fn in Unity)
            settings.ApplyModifiedProperties(); // apply changes made with the slider
        }
    }
}
