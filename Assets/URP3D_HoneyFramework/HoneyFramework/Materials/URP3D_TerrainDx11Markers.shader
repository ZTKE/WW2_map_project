// 曲面细分shader, 参考: https://zhuanlan.zhihu.com/p/359999755
// 微软文档: https://learn.microsoft.com/en-us/windows/win32/direct3d11/direct3d-11-advanced-stages-tessellation
Shader "HoneyFramework/URP3D/TerrainDx11WithMarkers" {
    Properties {
        _MainTex ("Base (RGB)", 2D) = "white" {}
        _Tess ("Tessellation", Range(1, 32)) = 4
        _MaxTessDistance ("Max Tess Distance", Range(1, 32)) = 20
        _MinTessDistance ("Min Tess Distance", Range(1, 32)) = 1
        _HeightTex ("Height Texture", 2D) = "gray" {}
        _Displacement ("Displacement", Range(0, 3.0)) = 1.5
        _MarkersGraphic ("Markers Graphic", 2D) = "black" {}
        // 标记RT宽度和高度为_MarkerSettings.z * _MarkerSettings.w, 也就是说这张图默认是128*128尺寸
        _MarkersPositionData ("Markers Position Data", 2D) = "black" {}
        // marker settings: (marker graphic count width,
        //                   marker graphic count height,
        //                   marker data width hex count, <- expected to be square for height
        //                   marker hex data size, <- number of following pixels of data for each hex
        _MarkerSettings ("Marker Settings", Vector) = (8, 8, 64, 2)

        // 国家颜色数据不需要_MarkerSettings.w, 也就是默认是64*64的RT贴图
        _CountriesColorData ("Countries Color Data", 2D) = "clear" {}

        // 国家颜色烘焙结果贴图
        _BakedCountriesColor ("Baked Countries Color", 2D) = "clear" {}
        _BakedCountriesColorBlur ("Baked Countries Color Blur", 2D) = "clear" {}
    }

    SubShader {
        Tags {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry+1"
        }
        LOD 300

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

            TEXTURE2D(_HeightTex);
            SAMPLER(sampler_HeightTex);

            TEXTURE2D(_MarkersGraphic);
            SAMPLER(sampler_MarkersGraphic);

            TEXTURE2D(_MarkersPositionData);
            SAMPLER(sampler_MarkersPositionData);

            TEXTURE2D(_BakedCountriesColor);
            SAMPLER(sampler_BakedCountriesColor);

            TEXTURE2D(_BakedCountriesColorBlur);
            SAMPLER(sampler_BakedCountriesColorBlur);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float _Tess;
                float _MaxTessDistance;
                float _MinTessDistance;
                float _Displacement;
                float4 _MarkerSettings;
            CBUFFER_END

            struct Attributes {
                float4 vertex : POSITION;
                float4 tangent : TANGENT;
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

            struct Vector3i {
                int x;
                int y;
                int z;
                // this value tells us uv of the hex. which is 0, 0 in one corner and 1, 1 in the oposite.
                // Perfect to draw texture for teh hex. Note that only single hex will have influence in each pixel! no blenddrawings here!
                float2 uv;
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

            float3 Disp(float3 vertex, float2 uv, float3 normal) {
                float d = (SAMPLE_TEXTURE2D_LOD(_HeightTex, sampler_HeightTex, uv, 0.0).a - 0.5) * _Displacement;
                // if its underground we will scaledown maximum depth
                half lessThanZero = step(d, 0.0);
                d *= 1.0 - lessThanZero * 0.4; // *= 0.6 or *= 1.0
                return vertex + normal * d;
            }

            Varyings vertAfter(Attributes i) {
                i.vertex.xyz = Disp(i.vertex.xyz, i.uv, i.normal);
                Varyings o;
                VertexPositionInputs v = GetVertexPositionInputs(i.vertex.xyz);
                o.vertex = v.positionCS;
                o.posWS = v.positionWS;
                o.normal = TransformObjectToWorldNormal(i.normal);
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

            // converts integer hex coordinates into flat world position used for uv and other 2d scapce calculations
            float2 ConvertToPosition(Vector3i v) {
                float cos30 = sqrt(3.0) * 0.5;
                float2 X = float2(1, 0);
                float2 Y = float2(-0.5, cos30);
                float2 Z = float2(-0.5, -cos30);
                return X * v.x + Y * v.y + Z * v.z;
            }

            // this code expects hex radius to be 1 for simplification.
            Vector3i GetHexCoord(float2 pos) {
                // Convert world flat coordinates into hex FLOAT position
                float TWO_THIRD = 2.0 / 3.0;
                float ONE_THIRD = 1.0 / 3.0;
                float COMPONENT = ONE_THIRD * sqrt(3.0);

                float x = TWO_THIRD * pos.x;
                float y = (COMPONENT * pos.y - ONE_THIRD * pos.x);
                float z = -x - y;

                // we cant use floating hex position, so before return we need to convert it to integer.
                // also its important to understand that floating point position contains some artifacts if converted separately into integers
                // we have to do some post-calculation cleanup to be able to recover from them.
                Vector3i v;
                v.x = round(x);
                v.y = round(y);
                v.z = round(z);

                // find delta between rounded and original value
                float dx = abs(v.x - x);
                float dy = abs(v.y - y);
                float dz = abs(v.z - z);

                // value which after rounding get most offset contains biggest artifacts, we want to discard it and recover form {a + b + c = 0} equation
                // if (dz > dy && dz > dx) {
                //     v.z = -v.x - v.y;
                // } else if (dy > dx) {
                //     v.y = -v.x - v.z;
                // } else { 
                //     v.x = -v.y - v.z; 
                // }
                int cond1 = step(dy, dz) * step(dx, dz); // if (dz > dy && dz > dx)
                int cond2 = step(dx, dy) * (1.0 - cond1); // else if (dy > dx)
                int cond3 = 1.0 - cond1 - cond2; // else
                int vx = cond3 * (-v.y - v.z) + (1 - cond3) * v.x;
                int vy = cond2 * (-v.x - v.z) + (1 - cond2) * v.y;
                int vz = cond1 * (-v.x - v.y) + (1 - cond1) * v.z;
                v.x = vx;
                v.y = vy;
                v.z = vz;

                // recover delta between testpoint and hex center as UV
                float2 center = ConvertToPosition(v);
                float2 offset = pos - center;
                v.uv = offset * 0.5 + float2(0.5, 0.5);

                return v;
            }

            half4 DrawMarkerLayer(half4 c, Vector3i v, float4 dataType, float4 dataAngle, int layer) {
                int type = round(dataType[layer] * _MarkerSettings.x * _MarkerSettings.y);
                if (type == 0) {
                    return c;
                }
                float2 markerPoint = float2(v.uv.x, v.uv.y) - float2(0.5, 0.5);
                // Short way of 2d rotation matrix
                float angle = TWO_PI * dataAngle[layer];
                float cosRot = cos(angle);
                float sinRot = sin(angle);
                float2 singleMarkerUV = float2(markerPoint.x * cosRot - markerPoint.y * sinRot,
                                               markerPoint.x * sinRot + markerPoint.y * cosRot);

                // Index of the type in atlas column and row
                int typeX = fmod(type, _MarkerSettings.x);
                int typeY = floor(_MarkerSettings.y - (type + 0.01) / _MarkerSettings.x);

                float2 atlasMarkerUV = singleMarkerUV + float2(0.5, 0.5) + float2(typeX, typeY);

                // make atlas UV to be within 0-1
                atlasMarkerUV.x = atlasMarkerUV.x / _MarkerSettings.x;
                atlasMarkerUV.y = atlasMarkerUV.y / _MarkerSettings.y;

                half4 marker = SAMPLE_TEXTURE2D(_MarkersGraphic, sampler_MarkersGraphic, atlasMarkerUV);
                return half4(lerp(c.rgb, marker.rgb, marker.a), c.a);
            }

            half4 frag(Varyings i) : SV_TARGET {
                half4 c = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
                float dataResolution = _MarkerSettings.z;
                int dataSize = round(_MarkerSettings.w);
                float2 pos = float2(i.posWS.x, i.posWS.z);
                Vector3i v = GetHexCoord(pos);
                float trueDataResolution = dataSize * dataResolution;
                float2 uvType = float2((v.x * dataSize + 0.5) / trueDataResolution, (v.y * dataSize + 0.5) / trueDataResolution);
                float2 uvAngle = uvType + float2(1.0 / trueDataResolution, 0);
                float4 dataType = SAMPLE_TEXTURE2D(_MarkersPositionData, sampler_MarkersPositionData, uvType);
                float4 dataAngle = SAMPLE_TEXTURE2D(_MarkersPositionData, sampler_MarkersPositionData, uvAngle);

                c = DrawMarkerLayer(c, v, dataType, dataAngle, 0); // 1st marker layer
                c = DrawMarkerLayer(c, v, dataType, dataAngle, 1); // 2nd marker layer
                c = DrawMarkerLayer(c, v, dataType, dataAngle, 2); // 3rd marker layer
                c = DrawMarkerLayer(c, v, dataType, dataAngle, 3); // 4th marker layer

                float2 uvBake = (i.uv - 0.5) * 0.5 + 0.5; // 烘焙的uv是原来uv的两倍大小, 需要居中缩放
                half4 bakedCountriesColor = SAMPLE_TEXTURE2D(_BakedCountriesColor, sampler_BakedCountriesColor, uvBake);
                half4 bakedCountriesColorBlur = SAMPLE_TEXTURE2D(_BakedCountriesColorBlur, sampler_BakedCountriesColorBlur, uvBake);

                float err = length(bakedCountriesColor - bakedCountriesColorBlur);
                bakedCountriesColor.a -= saturate(1.0 - err * 2.0) * 0.9;
                bakedCountriesColor.rgb -= smoothstep(0.4, 0.45, err) * 0.4;
                bakedCountriesColor = saturate(bakedCountriesColor);

                float t = lerp(0.3, 1.0, (sin(_Time.y * PI) + 1.0) * 0.5);
                c.rgb = lerp(c.rgb, bakedCountriesColor.rgb, bakedCountriesColor.a * t);

                half4 albedo = half4(c.rgb, 1.0);

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

            Varyings vert(Attributes i) {
                Varyings o;
                VertexPositionInputs v = GetVertexPositionInputs(i.vertex.xyz);
                o.vertex = v.positionCS;
                float3 n = TransformObjectToWorldNormal(i.normal);
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

            Varyings vert(Attributes i) {
                Varyings o;
                o.vertex = TransformObjectToHClip(i.vertex.xyz);
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

            TEXTURE2D(_HeightTex);
            SAMPLER(sampler_HeightTex);

            // 需要保持和"UniversalForward"的布局一致
            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float _Tess;
                float _MaxTessDistance;
                float _MinTessDistance;
                float _Displacement;
                float4 _MarkerSettings;
            CBUFFER_END

            struct Attributes {
                float4 vertex : POSITION;
                float4 tangent : TANGENT;
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
                float4 vertex : SV_POSITION;
                half3 normal : TEXCOORD0;
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

            float3 Disp(float3 vertex, float2 uv, float3 normal) {
                float d = (SAMPLE_TEXTURE2D_LOD(_HeightTex, sampler_HeightTex, uv, 0.0).a - 0.5) * _Displacement;
                // if its underground we will scaledown maximum depth
                half lessThanZero = step(d, 0.0);
                d *= 1.0 - lessThanZero * 0.4; // *= 0.6 or *= 1.0
                return vertex + normal * d;
            }

            Varyings vertAfter(Attributes i) {
                i.vertex.xyz = Disp(i.vertex.xyz, i.uv, i.normal);
                Varyings o = (Varyings)0;
                o.vertex = TransformObjectToHClip(i.vertex.xyz);
                o.normal = TransformObjectToWorldNormal(i.normal);
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

        Pass {
            Name "BakeCountriesColorPass" // 专门用于烘焙的Pass
            Tags {
                "LightMode" = "Meta"
            }

            Blend One Zero, One Zero
            Cull Back
            ZTest LEqual
            ZWrite On

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            TEXTURE2D(_CountriesColorData);
            SAMPLER(sampler_CountriesColorData);

            float4 _ChunkRect;
            float4 _BakeTargetCountryColor;

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float _Tess;
                float _MaxTessDistance;
                float _MinTessDistance;
                float _Displacement;
                float4 _MarkerSettings;
            CBUFFER_END

            struct Attributes {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings {
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Vector3i {
                int x;
                int y;
                int z;
                // this value tells us uv of the hex. which is 0, 0 in one corner and 1, 1 in the oposite.
                // Perfect to draw texture for teh hex. Note that only single hex will have influence in each pixel! no blenddrawings here!
                float2 uv;
            };

            Varyings vert(Attributes i) {
                Varyings o = (Varyings)0;
                o.vertex = TransformObjectToHClip(i.vertex.xyz);
                o.uv = TRANSFORM_TEX(i.uv, _MainTex);
                return o;
            }

            // converts integer hex coordinates into flat world position used for uv and other 2d scapce calculations
            float2 ConvertToPosition(Vector3i v) {
                float cos30 = sqrt(3.0) * 0.5;
                float2 X = float2(1, 0);
                float2 Y = float2(-0.5, cos30);
                float2 Z = float2(-0.5, -cos30);
                return X * v.x + Y * v.y + Z * v.z;
            }

            // this code expects hex radius to be 1 for simplification.
            Vector3i GetHexCoord(float2 pos) {
                // Convert world flat coordinates into hex FLOAT position
                float TWO_THIRD = 2.0 / 3.0;
                float ONE_THIRD = 1.0 / 3.0;
                float COMPONENT = ONE_THIRD * sqrt(3.0);

                float x = TWO_THIRD * pos.x;
                float y = (COMPONENT * pos.y - ONE_THIRD * pos.x);
                float z = -x - y;

                // we cant use floating hex position, so before return we need to convert it to integer.
                // also its important to understand that floating point position contains some artifacts if converted separately into integers
                // we have to do some post-calculation cleanup to be able to recover from them.
                Vector3i v;
                v.x = round(x);
                v.y = round(y);
                v.z = round(z);

                // find delta between rounded and original value
                float dx = abs(v.x - x);
                float dy = abs(v.y - y);
                float dz = abs(v.z - z);

                // value which after rounding get most offset contains biggest artifacts, we want to discard it and recover form {a + b + c = 0} equation
                // if (dz > dy && dz > dx) {
                //     v.z = -v.x - v.y;
                // } else if (dy > dx) {
                //     v.y = -v.x - v.z;
                // } else { 
                //     v.x = -v.y - v.z; 
                // }
                int cond1 = step(dy, dz) * step(dx, dz); // if (dz > dy && dz > dx)
                int cond2 = step(dx, dy) * (1.0 - cond1); // else if (dy > dx)
                int cond3 = 1.0 - cond1 - cond2; // else
                int vx = cond3 * (-v.y - v.z) + (1 - cond3) * v.x;
                int vy = cond2 * (-v.x - v.z) + (1 - cond2) * v.y;
                int vz = cond1 * (-v.x - v.y) + (1 - cond1) * v.z;
                v.x = vx;
                v.y = vy;
                v.z = vz;

                // recover delta between testpoint and hex center as UV
                float2 center = ConvertToPosition(v);
                float2 offset = pos - center;
                v.uv = offset * 0.5 + float2(0.5, 0.5);

                return v;
            }

            half4 frag(Varyings i) : SV_TARGET {
                float2 pos = _ChunkRect.xy + (0.5 - i.uv) * _ChunkRect.zw * 2.0; // 居中, 然后*2.0扩大读取范围
                Vector3i v = GetHexCoord(pos);
                float2 uv = float2((v.x + 0.5) / _MarkerSettings.z, (v.y + 0.5) / _MarkerSettings.z);
                half4 col = SAMPLE_TEXTURE2D(_CountriesColorData, sampler_CountriesColorData, uv);
                if (_BakeTargetCountryColor.a < 0.01) {
                    return col;
                }
                float err = length(col.rgb - _BakeTargetCountryColor.rgb);
                if (err > 0.01) {
                    discard;
                }
                return col;
            }
            ENDHLSL
        }

        Pass {
            Name "BakeCountriesColorBlurPass" // 专门用于烘焙的Pass
            Tags {
                "LightMode" = "Meta"
            }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            TEXTURE2D(_BakedCountriesColor);
            SAMPLER(sampler_BakedCountriesColor);

            TEXTURE2D(_BakedCountriesColorBlur);
            SAMPLER(sampler_BakedCountriesColorBlur);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float _Tess;
                float _MaxTessDistance;
                float _MinTessDistance;
                float _Displacement;
                float4 _MarkerSettings;
            CBUFFER_END

            struct Attributes {
                float4 vertex : POSITION;
                float4 tangent : TANGENT;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
            };

            struct Varyings {
                float4 color : COLOR;
                float3 normal : NORMAL;
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 posWS: TEXCOORD1;
            };

            Varyings vert(Attributes i) {
                Varyings o = (Varyings)0;
                o.vertex = TransformObjectToHClip(i.vertex.xyz);
                o.uv = TRANSFORM_TEX(i.uv, _MainTex);
                return o;
            }

            half4 frag(Varyings i) : SV_TARGET {
                half4 color = SAMPLE_TEXTURE2D(_BakedCountriesColor, sampler_BakedCountriesColor, i.uv);
                half4 blur = SAMPLE_TEXTURE2D(_BakedCountriesColorBlur, sampler_BakedCountriesColorBlur, i.uv);
                blur.a *= color.a;
                return blur;
            }

            ENDHLSL
        }

        Pass {
            Name "BakeCountriesColorBlurCombinePass" // 专门用于烘焙的Pass
            Tags {
                "LightMode" = "Meta"
            }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            TEXTURE2D(_BakedCountriesColorBlur);
            SAMPLER(sampler_BakedCountriesColorBlur);

            TEXTURE2D(_BakedCountriesColorBlurCombine);
            SAMPLER(sampler_BakedCountriesColorBlurCombine);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float _Tess;
                float _MaxTessDistance;
                float _MinTessDistance;
                float _Displacement;
                float4 _MarkerSettings;
            CBUFFER_END

            struct Attributes {
                float4 vertex : POSITION;
                float4 tangent : TANGENT;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
            };

            struct Varyings {
                float4 color : COLOR;
                float3 normal : NORMAL;
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 posWS: TEXCOORD1;
            };

            Varyings vert(Attributes i) {
                Varyings o = (Varyings)0;
                o.vertex = TransformObjectToHClip(i.vertex.xyz);
                o.uv = TRANSFORM_TEX(i.uv, _MainTex);
                return o;
            }

            half4 frag(Varyings i) : SV_TARGET {
                half4 c0 = SAMPLE_TEXTURE2D(_BakedCountriesColorBlur, sampler_BakedCountriesColorBlur, i.uv);
                half4 c1 = SAMPLE_TEXTURE2D(_BakedCountriesColorBlurCombine, sampler_BakedCountriesColorBlurCombine, i.uv);
                half4 c = lerp(c0, c1, c1.a);
                if (c.a < 0.5) {
                    return 0.0;
                }
                c.rgb /= c.a;
                return c;
            }

            ENDHLSL
        }
    }
}
