using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class DepthCopyFeature : ScriptableRendererFeature {
    private DepthCopyPass depthCopyPass;

    public override void Create() {
        depthCopyPass = new DepthCopyPass();
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData) {
        CameraData d = renderingData.cameraData;
        if (d.cameraType != CameraType.Game || d.renderType != CameraRenderType.Base) {
            return;
        }
        renderer.EnqueuePass(depthCopyPass);
    }

    private class DepthCopyPass : ScriptableRenderPass {
        private RTHandle depthSource;
        private RTHandle depthCopyHandle;
        private const string TEX_NAME = "_CopiedDepthTexture";
        private static readonly int TEX_ID = Shader.PropertyToID(TEX_NAME);

        public DepthCopyPass() {
            renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData) {
            var cameraData = renderingData.cameraData;
            var renderer = cameraData.renderer;
            depthSource = renderer.cameraDepthTargetHandle;

            RenderTextureDescriptor descriptor = cameraData.cameraTargetDescriptor;
            descriptor.depthBufferBits = 0; // 我们只需要颜色通道来存储深度值
            descriptor.colorFormat = RenderTextureFormat.RFloat; // 单通道浮点格式最适合存储深度
            descriptor.msaaSamples = 1; // 不需要 MSAA，复制为单一深度

            RenderingUtils.ReAllocateIfNeeded(
                ref depthCopyHandle,
                descriptor,
                FilterMode.Point,
                TextureWrapMode.Clamp,
                name: TEX_NAME
            );

            ConfigureTarget(depthCopyHandle);
            ConfigureClear(ClearFlag.None, Color.clear);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData) {
            const string CMD_NAME = "DepthCopyPass";
            CommandBuffer cmd = CommandBufferPool.Get(CMD_NAME);
            using (new ProfilingScope(cmd, new ProfilingSampler(CMD_NAME))) {
                Blitter.BlitCameraTexture(cmd, depthSource, depthCopyHandle);
                cmd.SetGlobalTexture(TEX_ID, depthCopyHandle);
            }
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd) {
            depthSource = null;
        }

        public override void OnFinishCameraStackRendering(CommandBuffer cmd) {
            base.OnFinishCameraStackRendering(cmd);
            if (depthCopyHandle != null) {
                RTHandles.Release(depthCopyHandle);
                depthCopyHandle = null;
            }
        }
    }
}
