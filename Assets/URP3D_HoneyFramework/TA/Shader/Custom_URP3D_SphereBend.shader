// 球面扭曲公式: https://www.desmos.com/calculator/atakwzdl5p?lang=zh-CN
Shader "Custom/URP3D/SphereBend" {
    Properties {
        _MainTex ("MainTex", 2D) = "white"{}
        _Color ("Color(RGB)", Color) = (1, 1, 1, 1)
        _Tess ("Tessellation", Range(1, 32)) = 4
        _MaxTessDistance ("Max Tess Distance", Range(1, 32)) = 20
        _MinTessDistance ("Min Tess Distance", Range(1, 32)) = 1
        _Radius ("Radius", Range(5.0, 1000.0)) = 5.0
    }

    SubShader {
        Tags {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry+0"
        }

        Pass {
            Name "Pass"
            Tags {
                "LightMode" = "UniversalForward"
            }

            Blend One Zero, One Zero
            Cull Back
            ZTest LEqual
            ZWrite On

            HLSLPROGRAM

            #pragma require tessellation
            #pragma require geometry

            #pragma vertex vert
            #pragma hull hull
            #pragma domain domain
            #pragma fragment frag

            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 4.6

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                half4 _Color;
                float _Tess;
                float _MaxTessDistance;
                float _MinTessDistance;
                float _Radius;
            CBUFFER_END

            struct Attributes {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
            };

            // 使用INTERNALTESSPOS代替POSITION语意, 其余和Attributes保持一致
            struct TessCtrlPoint {
                float4 vertex : INTERNALTESSPOS;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
            };

            struct TessFactors {
                float edge[3] : SV_TessFactor;
                float inside : SV_InsideTessFactor;
            };

            struct Varyings {
                float4 color : COLOR;
                float3 normal : NORMAL;
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 posWS: TEXCOORD1;
            };

            // vert只需要原封不动传递数据给tess
            TessCtrlPoint vert(Attributes i) {
                TessCtrlPoint o;
                o.vertex = i.vertex;
                o.uv = i.uv;
                o.normal = i.normal;
                o.color = i.color;
                return o;
            }

            // 随着距相机的距离减少细分数
            float CalcDistanceTessFactor(float4 vertex, float minDist, float maxDist, float tess) {
                float3 wp = TransformObjectToWorld(vertex.xyz);
                float dist = distance(wp, GetCameraPositionWS());
                float f = clamp(1.0 - (dist - minDist) / (maxDist - minDist), 0.01, 1.0) * tess;
                return f;
            }

            TessFactors patch(InputPatch<TessCtrlPoint, 3> i) {
                TessFactors o;
                float minDist = _MinTessDistance;
                float maxDist = _MaxTessDistance;
                float t = _Tess;
                float edge0 = CalcDistanceTessFactor(i[0].vertex, minDist, maxDist, t);
                float edge1 = CalcDistanceTessFactor(i[1].vertex, minDist, maxDist, t);
                float edge2 = CalcDistanceTessFactor(i[2].vertex, minDist, maxDist, t);
                o.edge[0] = (edge1 + edge2) * 0.5;
                o.edge[1] = (edge2 + edge0) * 0.5;
                o.edge[2] = (edge0 + edge1) * 0.5;
                o.inside = (edge0 + edge1 + edge2) * 0.333333333;
                return o;
            }

            #define CTRL_POINTS 3
            [domain("tri")]
            [outputcontrolpoints(CTRL_POINTS)]
            [outputtopology("triangle_cw")]
            [partitioning("fractional_even")]
            [patchconstantfunc("patch")]
            TessCtrlPoint hull(InputPatch<TessCtrlPoint, CTRL_POINTS> p, uint id : SV_OutputControlPointID) {
                return p[id];
            }

            Varyings vertAfter(Attributes i) {
                Varyings o;

                // 球面扭曲
                float r = _Radius;
                float3 vi = i.vertex.xyz;
                float x = vi.x;
                float z = vi.z;
                float t = sqrt(x * x + z * z);
                float a = PI * 0.5 - t / r;
                float y = r * (sin(a) - 1.0);
                float d = r * cos(a);
                float2 xz = float2(x, z);
                if (length(xz) > 0.01) {
                    xz = d * normalize(xz);
                }
                vi.y = y;
                vi.xz = xz;

                // 重构法线
                float3 ni = i.normal;
                float3 so = float3(0.0, -r, 0.0);
                ni = normalize(vi - so);

                VertexPositionInputs v = GetVertexPositionInputs(vi);
                o.vertex = v.positionCS;
                o.posWS = v.positionWS;
                o.normal = TransformObjectToWorldNormal(ni);
                o.uv = TRANSFORM_TEX(i.uv, _MainTex);
                o.color = i.color;
                return o;
            }

            [domain("tri")]
            Varyings domain(TessFactors f, OutputPatch<TessCtrlPoint, 3> p, float3 uvw : SV_DomainLocation) {
                Attributes i;

                #define DOMAIN_LERP(prop) i.prop = p[0].prop * uvw.x + p[1].prop * uvw.y + p[2].prop * uvw.z
                DOMAIN_LERP(vertex);
                DOMAIN_LERP(uv);
                DOMAIN_LERP(color);
                DOMAIN_LERP(normal);

                return vertAfter(i);
            }

            #define TEST_GRID
            half4 frag(Varyings i) : SV_TARGET {
                half4 albedo = _Color;

                #ifdef TEST_GRID
                    const float GRID_SIZE = 10.0;
                    const float LINE_WIDTH = 0.01;

                    float2 grid2 = step(1.0 - LINE_WIDTH, cos(i.uv * TWO_PI * GRID_SIZE));
                    float grid = min(grid2.x + grid2.y, 1.0);
                    float circle = step(1.0 - LINE_WIDTH, cos(length(i.uv - 0.5) * TWO_PI * GRID_SIZE));

                    albedo -= half4((saturate(grid + circle) * 0.5).xxx, 0.0);
                #endif

                albedo *= SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);

                InputData d = (InputData)0;
                d.positionWS = i.posWS;
                d.normalWS = normalize(i.normal);
                d.viewDirectionWS = GetWorldSpaceNormalizeViewDir(i.posWS);
                d.shadowCoord = TransformWorldToShadowCoord(i.posWS);

                SurfaceData s = (SurfaceData)0;
                s.albedo = albedo.rgb;
                s.alpha = albedo.a;

                return UniversalFragmentPBR(d, s);
            }

            ENDHLSL
        }

        Pass {
            Name "ShadowCaster"
            Tags {
                "LightMode" = "ShadowCaster"
            }

            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct Varyings {
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                half4 _Color;
                float _Tess;
                float _MaxTessDistance;
                float _MinTessDistance;
                float _Radius;
            CBUFFER_END

            Varyings vert(Attributes i) {
                Varyings o;

                // 球面扭曲
                float r = _Radius;
                float3 vi = i.vertex.xyz;
                float x = vi.x;
                float z = vi.z;
                float t = sqrt(x * x + z * z);
                float a = PI * 0.5 - t / r;
                float y = r * (sin(a) - 1.0);
                float d = r * cos(a);
                float2 xz = float2(x, z);
                if (length(xz) > 0.01) {
                    xz = d * normalize(xz);
                }
                vi.y = y;
                vi.xz = xz;

                // 重构法线
                float3 ni = i.normal;
                float3 so = float3(0.0, -r, 0.0);
                ni = normalize(vi - so);

                VertexPositionInputs v = GetVertexPositionInputs(vi);
                o.vertex = v.positionCS;
                float3 n = TransformObjectToWorldNormal(ni);
                Light mainLight = GetMainLight();
                float3 l = mainLight.direction;
                float3 p = v.positionWS;
                ApplyShadowBias(p, n, l);
                o.uv = i.uv;
                return o;
            }

            half4 frag(Varyings i) : SV_TARGET {
                return 0;
            }
            ENDHLSL
        }

        Pass {
            Name "DepthOnly"
            Tags {
                "LightMode" = "DepthOnly"
            }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes {
                float4 vertex : POSITION;
            };

            struct Varyings {
                float4 vertex : SV_POSITION;
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                half4 _Color;
                float _Tess;
                float _MaxTessDistance;
                float _MinTessDistance;
                float _Radius;
            CBUFFER_END

            Varyings vert(Attributes i) {
                Varyings o;

                // 球面扭曲
                float r = _Radius;
                float3 vi = i.vertex.xyz;
                float x = vi.x;
                float z = vi.z;
                float t = sqrt(x * x + z * z);
                float a = PI * 0.5 - t / r;
                float y = r * (sin(a) - 1.0);
                float d = r * cos(a);
                float2 xz = float2(x, z);
                if (length(xz) > 0.01) {
                    xz = d * normalize(xz);
                }
                vi.y = y;
                vi.xz = xz;

                o.vertex = TransformObjectToHClip(vi);
                return o;
            }

            half4 frag(Varyings i) : SV_Target {
                return 0;
            }
            ENDHLSL
        }

        Pass {
            Name "DepthNormals"
            Tags {
                "LightMode" = "DepthNormals"
            }

            HLSLPROGRAM
            #pragma require tessellation
            #pragma require geometry

            #pragma vertex vert
            #pragma hull hull
            #pragma domain domain
            #pragma fragment frag

            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 4.6

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                half4 _Color;
                float _Tess;
                float _MaxTessDistance;
                float _MinTessDistance;
                float _Radius;
            CBUFFER_END

            struct Attributes {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
            };

            // 使用INTERNALTESSPOS代替POSITION语意, 其余和Attributes保持一致
            struct TessCtrlPoint {
                float4 vertex : INTERNALTESSPOS;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct TessFactors {
                float edge[3] : SV_TessFactor;
                float inside : SV_InsideTessFactor;
            };

            struct Varyings {
                float3 normal : NORMAL;
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            // vert只需要原封不动传递数据给tess
            TessCtrlPoint vert(Attributes i) {
                TessCtrlPoint o;
                o.vertex = i.vertex;
                o.uv = i.uv;
                o.normal = i.normal;
                return o;
            }

            // 随着距相机的距离减少细分数
            float CalcDistanceTessFactor(float4 vertex, float minDist, float maxDist, float tess) {
                float3 wp = TransformObjectToWorld(vertex.xyz);
                float dist = distance(wp, GetCameraPositionWS());
                float f = clamp(1.0 - (dist - minDist) / (maxDist - minDist), 0.01, 1.0) * tess;
                return f;
            }

            TessFactors patch(InputPatch<TessCtrlPoint, 3> i) {
                TessFactors o;
                float minDist = _MinTessDistance;
                float maxDist = _MaxTessDistance;
                float t = _Tess;
                float edge0 = CalcDistanceTessFactor(i[0].vertex, minDist, maxDist, t);
                float edge1 = CalcDistanceTessFactor(i[1].vertex, minDist, maxDist, t);
                float edge2 = CalcDistanceTessFactor(i[2].vertex, minDist, maxDist, t);
                o.edge[0] = (edge1 + edge2) * 0.5;
                o.edge[1] = (edge2 + edge0) * 0.5;
                o.edge[2] = (edge0 + edge1) * 0.5;
                o.inside = (edge0 + edge1 + edge2) * 0.333333333;
                return o;
            }

            #define CTRL_POINTS 3
            [domain("tri")]
            [outputcontrolpoints(CTRL_POINTS)]
            [outputtopology("triangle_cw")]
            [partitioning("fractional_even")]
            [patchconstantfunc("patch")]
            TessCtrlPoint hull(InputPatch<TessCtrlPoint, CTRL_POINTS> p, uint id : SV_OutputControlPointID) {
                return p[id];
            }

            Varyings vertAfter(Attributes i) {
                Varyings o = (Varyings)0;

                // 球面扭曲
                float r = _Radius;
                float3 vi = i.vertex.xyz;
                float x = vi.x;
                float z = vi.z;
                float t = sqrt(x * x + z * z);
                float a = PI * 0.5 - t / r;
                float y = r * (sin(a) - 1.0);
                float d = r * cos(a);
                float2 xz = float2(x, z);
                if (length(xz) > 0.01) {
                    xz = d * normalize(xz);
                }
                vi.y = y;
                vi.xz = xz;

                // 重构法线
                float3 ni = i.normal;
                float3 so = float3(0.0, -r, 0.0);
                ni = normalize(vi - so);

                o.vertex = TransformObjectToHClip(vi);
                o.normal = TransformObjectToWorldNormal(ni);
                return o;
            }

            [domain("tri")]
            Varyings domain(TessFactors f, OutputPatch<TessCtrlPoint, 3> p, float3 uvw : SV_DomainLocation) {
                Attributes i;

                #define DOMAIN_LERP(prop) i.prop = p[0].prop * uvw.x + p[1].prop * uvw.y + p[2].prop * uvw.z
                DOMAIN_LERP(vertex);
                DOMAIN_LERP(uv);
                DOMAIN_LERP(normal);

                return vertAfter(i);
            }

            void frag(Varyings i, out half4 outNormalWS : SV_Target0) {
                outNormalWS = half4(NormalizeNormalPerPixel(i.normal), 0.0);
            }
            ENDHLSL
        }
    }
}
