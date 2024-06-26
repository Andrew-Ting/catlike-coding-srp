using UnityEngine;
using UnityEngine.Rendering;

public class MeshBall : MonoBehaviour
{

    static int baseColorId = Shader.PropertyToID("_BaseColor"),
        metallicId = Shader.PropertyToID("_Metallic"),
        smoothnessId = Shader.PropertyToID("_Smoothness");

    [SerializeField]
    Mesh mesh = default;

    [SerializeField]
    Material material = default;

    Matrix4x4[] matrices = new Matrix4x4[1023];
    Vector4[] baseColors = new Vector4[1023];

    MaterialPropertyBlock block;

    float[]
        metallic = new float[1023],
        smoothness = new float[1023];

    [SerializeField]
    LightProbeProxyVolume lightProbeVolume = null;

    void Awake()
    {
        GraphicsSettings.useScriptableRenderPipelineBatching = true;
        for (int i = 0; i < matrices.Length; i++)
        {
            matrices[i] = Matrix4x4.TRS(
                Random.insideUnitSphere * 10f, Quaternion.Euler(
                    Random.value * 360f, Random.value * 360f, Random.value * 360f
                ), Vector3.one * Random.Range(0.5f, 1.5f)
            );
            baseColors[i] =
                new Vector4(Random.value, Random.value, Random.value, Random.Range(0.5f, 1f));
            metallic[i] = Random.value < 0.25f ? 1f : 0f;
            smoothness[i] = Random.Range(0.05f, 0.95f);
        }
    }

    void Update()
    {
        if (block == null)
        {
            block = new MaterialPropertyBlock();
            block.SetVectorArray(baseColorId, baseColors);
            block.SetFloatArray(metallicId, metallic);
            block.SetFloatArray(smoothnessId, smoothness);

            if (!lightProbeVolume) // only compute light probes when they are customprovided, not when we are using proxy volumes
            {
                var positions = new Vector3[1023];
                for (int i = 0; i < matrices.Length; i++)
                {
                    positions[i] = matrices[i].GetColumn(3); // grab positions of all GPU instanced spheres in 3D space
                }
                var lightProbes = new SphericalHarmonicsL2[1023];
                var occlusionProbes = new Vector4[1023];
                LightProbes.CalculateInterpolatedLightAndOcclusionProbes(
                    positions, lightProbes, occlusionProbes
                );
                block.CopySHCoefficientArraysFrom(lightProbes);
            }
        }

        // only defined when GPU instancing is enabled
        Graphics.DrawMeshInstanced(mesh, 0, material, matrices, 1023, block, ShadowCastingMode.On, true, 0, null, lightProbeVolume ?
                LightProbeUsage.UseProxyVolume : LightProbeUsage.CustomProvided, lightProbeVolume); // draws in order of array data (no sorting); no culling, but will disappear when completely out of view frustum
    }
}