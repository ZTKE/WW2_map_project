using UnityEngine;
using System.Collections;
using System.Collections.Generic;
using System.Linq;

namespace HoneyFramework {
    /*
     *  Core class which works on preparation of the diffuse and height texture assets for terrain
     */
    public class WorldOven : MonoBehaviour {
        static private WorldOven instance;

        static public Vector3 lightSourceDirection = new Vector3(0.1f, -0.025f, 0.0f);

        // static runtime data
        public Camera bakingCamera;
        public GameObject quadBase;
        public GameObject hexOutlineBase;
        public GameObject riverBase;

        public Material mixerMaterial;
        public Material heightMaterial;
        public Material riverHeightMaterial; // this material is alternative height material for rivers
        public Material shadowsAndHeightMaterial;
        public Material diffuseMaterial;

        public Material riverSmoothenerMaterial;
        public Material blurMaterial;

        public Texture riverSmoothenerTexture;

        public int randomIndex;

        //dynamic data
        static public List<Chunk> dirtyChunks = new List<Chunk>();
        List<MeshRenderer> quadCollection = new List<MeshRenderer>();
        List<MeshRenderer> hexOutlineCollection = new List<MeshRenderer>();
        Dictionary<Hex, MeshRenderer> displayCollection = new Dictionary<Hex, MeshRenderer>();
        List<MeshRenderer> riverSections = new List<MeshRenderer>();
        List<MeshRenderer> riverSmoothenerSections = new List<MeshRenderer>();

        RenderTexture mixerRT;
        RenderTexture heightRT;
        RenderTexture heightRTOffset1;
        RenderTexture heightRTOffset2;
        RenderTexture shadowsAndHeightRT;
        RenderTexture diffuseRT;
        Chunk currentChunk;
        bool baking = false;

        int bakeSize = 256; // Chunk.TextureSize;
        Color32[] clearColors;

        /// <summary>
        /// Check all core assets are in place
        /// </summary>
        /// <returns></returns>
        void Awake() {
            if (bakingCamera == null) { Debug.LogError("Missing baking camera. This camera is used to define rendering parameters for textures during baking process"); }
            ;
            if (quadBase == null) { Debug.LogError("Missing quad base, we will need one to use as a base to draw single hex during baking"); }
            ;
            if (hexOutlineBase == null) { Debug.LogError("Missing hexOutlineBase, this gameobject contains quad with hex outline graphic which is rendered onto the map"); }
            ;
            if (riverBase == null) { Debug.LogError("River base is a game object which is used by divers during linking mesh with material and then later for baking process"); }
            ;

            if (mixerMaterial == null) { Debug.LogError("Missing mixer material. This material defines how hexes blend with each other and produces blending result mixer texture"); }
            ;
            if (heightMaterial == null) { Debug.LogError("Missing height material. This material uses mixer result texture, per hex mixer and height texture to define height shape of the chunk"); }
            ;
            if (riverHeightMaterial == null) { Debug.LogError("Missing river height material. This custom material handles drawing special case of height for rivers"); }
            ;
            if (shadowsAndHeightMaterial == null) { Debug.LogError("Missing shadow and height material. This material is producing terrain shadowing and copies height to alpha channel from which it might be easier converted to Alpha8 texture"); }
            ;
            if (diffuseMaterial == null) { Debug.LogError("Missing diffuse material which uses many textures to define colors in chunk pixels"); }
            ;

            if (riverSmoothenerMaterial == null) { Debug.LogError("Missing river smoothener material, rivers use this material to ensure terrain shape is better fitting river existence (isn't to sharp which would be very noticeable with almost any reasonable terrain resolution)."); }
            ;

            randomIndex = Random.Range(0, int.MaxValue);

            bakeSize = Chunk.TextureSize;
            clearColors = new Color32[bakeSize * bakeSize];
        }

        /// <summary>
        /// 
        /// </summary>
        /// <returns></returns>
        private void Start() {
            RiverFactory.BuildRiversMeshes();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <returns></returns>
        private void Cleanup() {
            MeshFilter[] mrs = GetComponentsInChildren<MeshFilter>();
            foreach (MeshFilter mr in mrs) {
                if (mr.sharedMesh != null) {
                    Destroy(mr.sharedMesh);
                }
            }
        }

        /// <summary>
        /// Returns oven instance
        /// </summary>
        /// <returns></returns>
        static public WorldOven GetInstance() {
            if (instance == null) {
                GameObject go = GameObject.Instantiate(World.instance.ovenBase.gameObject) as GameObject;
                instance = go.GetComponent<WorldOven>();
            }

            return instance;
        }

        /// <summary>
        /// provides new chunk which needs to be baked.
        /// Note that this will work only if oven still exists and/or works
        /// </summary>
        /// <param name="c"></param>
        /// <returns></returns>
        static public void AddDirtyChunk(Chunk c) {
            if (!dirtyChunks.Contains(c)) {
                c.InvalidateChunkData();
                dirtyChunks.Add(c);

                //ensure instance is there to process it because if previous process end fast enough world oven could be destroyed to free memory and assets
                GetInstance();

                World.GetInstance().status = World.Status.TerrainGeneration;
            }
        }

        /// <summary>
        /// If baking were requested this function will handle starting all required processes and default settings required for initial pass
        /// </summary>
        /// <returns></returns>
        void Update() {
            if (dirtyChunks.Count > 0 && baking == false) {
                baking = true;

                bakingCamera.orthographicSize = Chunk.ChunkSizeInWorld * 0.5f;
                bakingCamera.aspect = 1.0f;

                quadBase.transform.localScale = new Vector3(Hex.hexTextureScale * 2.0f, Hex.hexTextureScale * 2.0f, Hex.hexTextureScale * 2.0f);

                GameObject root = GameObject.Find("RiverRoot");
                foreach (Transform t in root.transform) {
                    MeshRenderer mr = t.GetComponent<MeshRenderer>();
                    if (mr != null) {
                        riverSections.Add(mr);
                    }
                }

                root = GameObject.Find("RiverSmoothener");
                foreach (Transform t in root.transform) {
                    MeshRenderer mr = t.GetComponent<MeshRenderer>();
                    if (mr != null) {
                        riverSmoothenerSections.Add(mr);
                    }
                }
                StartCoroutine("Baking");
            }
        }

        /// <summary>
        /// Most complex functionality which ensures all stages of baking take place in order and that they allow world to update form time to time instead of freezing everything.
        /// </summary>
        /// <returns></returns>
        IEnumerator Baking() {
            CoroutineHelper.StartTimer();

            while (dirtyChunks.Count > 0) {
                //setup chunk scene in order required by blending
                PreparationStage();
                if (CoroutineHelper.CheckIfPassed(30)) { yield return null; CoroutineHelper.StartTimer(); }

                // Mixer        
                //This texture later defines how different hexes blend each other. It bakes highest domination value taking into account distance from hex center and mixer texture.
                //Uses "Blending Max" which produces result by comparing previous color value with new result from shader:  
                //R = R1 > R2 ? R1 : R2; 
                //G = G1 > G2 ? G1 : G2;
                //B = B1 > B2 ? B1 : B2; 
                //A = A1 > A2 ? A1 : A2;
                BakingMixerStage();
                if (CoroutineHelper.CheckIfPassed(30)) { yield return null; CoroutineHelper.StartTimer(); }

                // Height        
                // defines how high terrain is. At this stage we blend using Mixer textures and previously prepared sum of mixers. By comparing both we know how strong our hex is within this point
                // Height is written to R, While writting strenght is based on A channel
                bakingCamera.orthographicSize = Chunk.ChunkSizeInWorld * 0.5f;
                BakingHeightStage();
                BlurTexture(heightRT, 1, 1, 1);
                if (CoroutineHelper.CheckIfPassed(30)) { yield return null; CoroutineHelper.StartTimer(); }

                // Offset heights are baked using the same settings 
                //small offset allows with comparison find shadow borders ensuring its sharpness
                //big offset ensures shadow body and coverage in irregular terrain and data artifacts
                bakingCamera.transform.localPosition = lightSourceDirection.normalized * 0.15f;  //small offset for shadow detail
                BakeTo(ref heightRTOffset1, 1);
                BlurTexture(heightRTOffset1, 1, 1, 1);
                if (CoroutineHelper.CheckIfPassed(30)) { yield return null; CoroutineHelper.StartTimer(); }

                bakingCamera.transform.localPosition = lightSourceDirection.normalized * 0.3f; //higher offset to get shadow body
                BakeTo(ref heightRTOffset2, 1);
                BlurTexture(heightRTOffset2, 1, 1, 1);
                bakingCamera.transform.localPosition = new Vector3(0.0f, 0.0f, 0.0f);
                if (CoroutineHelper.CheckIfPassed(30)) { yield return null; CoroutineHelper.StartTimer(); }

                shadowsAndHeightRT = ProduceShadowsAndHeightTexture(heightRT, heightRTOffset1, heightRTOffset2);
                if (CoroutineHelper.CheckIfPassed(30)) { yield return null; CoroutineHelper.StartTimer(); }

                // Bake Diffuse                        
                foreach (MeshRenderer mr in hexOutlineCollection) {
                    Vector3 pos = mr.transform.localPosition;
                    pos.z = 5;
                    mr.transform.localPosition = pos;
                }

                ReorderHexesPlacingWaterOnTop();
                if (CoroutineHelper.CheckIfPassed(30)) { yield return null; CoroutineHelper.StartTimer(); }

                BakingDiffuseStage();
                if (CoroutineHelper.CheckIfPassed(30)) { yield return null; CoroutineHelper.StartTimer(); }

                //turn off everything from camera view
                foreach (MeshRenderer mr in quadCollection) {
                    if (mr.GetComponent<Renderer>().material != null) { GameObject.Destroy(mr.GetComponent<Renderer>().material); }
                    mr.gameObject.SetActive(false);
                }
                foreach (MeshRenderer mr in hexOutlineCollection) {
                    mr.gameObject.SetActive(false);
                }

                // Copy Height to Texture2D (ARGB) because we cant render directly to Alpha8. 
                Texture2D texture;
                RenderTexture.active = shadowsAndHeightRT;
                texture = new Texture2D(Chunk.TextureSize >> 1, Chunk.TextureSize >> 1, TextureFormat.ARGB32, false);
                texture.wrapMode = TextureWrapMode.Clamp;
                texture.ReadPixels(new Rect(0, 0, Chunk.TextureSize >> 1, Chunk.TextureSize >> 1), 0, 0);
                texture.Apply();

                //Convert height to Alpha8, its reasonably cheap and good even uncompressed format. Not compressed format saves us form artifacts near shaped water borders and mountain tops
                if (CoroutineHelper.CheckIfPassed(30)) { yield return null; CoroutineHelper.StartTimer(); }
                Texture2D gScale = new Texture2D(Chunk.TextureSize >> 1, Chunk.TextureSize >> 1, TextureFormat.Alpha8, false);
                gScale.wrapMode = TextureWrapMode.Clamp;
                Color32[] data = texture.GetPixels32();

                gScale.SetPixels32(data);
                gScale.Apply();

                gScale.name = "Height" + currentChunk.position;

                //if this is chunk refresh we need to destroy old texture soon
                if (currentChunk.height != null) currentChunk.texturesForCleanup.Add(currentChunk.height);
                currentChunk.height = gScale;

                //source texture will not be used anymore
                GameObject.Destroy(texture);
                if (CoroutineHelper.CheckIfPassed(30)) { yield return null; CoroutineHelper.StartTimer(); }

                //Render shadow and light to scaled down texture and copy it to Texture2D
                int scaleDownPower = 4; //scaling it down 4 powers will resize e.g.: from 2048 to 128 making it marginally small
                RenderTexture shadowTarget = RenderTargetManager.GetNewTexture(Chunk.TextureSize >> scaleDownPower, Chunk.TextureSize >> scaleDownPower);
                Graphics.Blit(shadowsAndHeightRT, shadowTarget);
                RenderTexture.active = shadowTarget;
                texture = new Texture2D(Chunk.TextureSize >> scaleDownPower, Chunk.TextureSize >> scaleDownPower, TextureFormat.RGB24, false);
                texture.wrapMode = TextureWrapMode.Clamp;
                texture.ReadPixels(new Rect(0, 0, Chunk.TextureSize >> scaleDownPower, Chunk.TextureSize >> scaleDownPower), 0, 0);
                texture.Apply();

                //  SaveImage.SaveJPG(texture, currentChunk.position.ToString() + "h", randomIndex.ToString());

                texture.Compress(false); //rgb24 will compress to 4 bits per pixel.
                texture.Apply();

                //if this is chunk refresh we need to destroy old texture soon
                if (currentChunk.shadows != null) currentChunk.texturesForCleanup.Add(currentChunk.shadows);
                currentChunk.shadows = texture;
                RenderTexture.active = null;
                shadowTarget.Release();

                if (CoroutineHelper.CheckIfPassed(30)) { yield return null; CoroutineHelper.StartTimer(); }

                // Copy Diffuse to Texture2D            
                RenderTexture.active = diffuseRT;
                texture = new Texture2D(Chunk.TextureSize, Chunk.TextureSize, TextureFormat.RGB24, false);
                texture.wrapMode = TextureWrapMode.Clamp;
                texture.ReadPixels(new Rect(0, 0, Chunk.TextureSize, Chunk.TextureSize), 0, 0);

                texture.name = "Diffuse" + currentChunk.position;
                //if this is chunk refresh we need to destroy old texture soon
                if (currentChunk.diffuse != null) currentChunk.texturesForCleanup.Add(currentChunk.diffuse);
                currentChunk.diffuse = texture;
                //   SaveImage.SaveJPG(texture, currentChunk.position.ToString() + "d", randomIndex.ToString());
                currentChunk.CompressDiffuse();

                RenderTexture.active = null;

                if (CoroutineHelper.CheckIfPassed(30)) { yield return null; CoroutineHelper.StartTimer(); }

                currentChunk.bakedCountriesColor = RenderTargetManager.GetNewTexture(bakeSize, bakeSize, 32, RenderTextureFormat.ARGB32, dontRelease: true);
                currentChunk.bakedCountriesColorBlur = RenderTargetManager.GetNewTexture(bakeSize, bakeSize, 32, RenderTextureFormat.ARGB32, dontRelease: true);

                if (CoroutineHelper.CheckIfPassed(30)) { yield return null; CoroutineHelper.StartTimer(); }

                bakingCamera.targetTexture = null;
                currentChunk.CreateGameObjectWithTextures();
                dirtyChunks.RemoveAt(0);

                World.GetInstance().ReadyToPolishChunk(currentChunk);
                RenderTargetManager.ReleaseAll();

                if (CoroutineHelper.CheckIfPassed(30)) { yield return null; CoroutineHelper.StartTimer(); }
            }

            if (World.GetInstance().StartPolishingWorld()) {

                MeshRenderer[] rArray = GetComponentsInChildren<MeshRenderer>(true) as MeshRenderer[];
                foreach (MeshRenderer r in rArray) {
                    if (r.material != null) {
                        GameObject.Destroy(r.material);
                    }
                }

                RenderTargetManager.DestroyAllUnusedTextures();
                Cleanup();
                // DestroyObject(gameObject); // 已弃用
                Destroy(gameObject);
                instance = null;
            }
        }

        /// <summary>
        /// Clears render targets and returns info if any of them was invalid. Which may indicate that texture was lost prematurely
        /// </summary>
        /// <param name="ready">true if textures could be cleared at this stage indicating "all correct" state </param>
        /// <param name="textures">list of the textures to get cleareds</param>
        /// <returns></returns>
        void CheckAndClear(ref bool ready, params RenderTexture[] textures) {
            foreach (RenderTexture rt in textures) {
                if (rt != null) {
                    //is texture not null but released by hardware by mistake? its possible something released it before we manage to use it!
                    if (!rt.IsCreated()) ready = false;
                    rt.Release();
                } else {
                    Debug.LogWarning("texture " + MHDebug.GetVariableName(() => rt) + "was null before clearing!");
                }
            }
        }


        /// <summary>
        /// Preparation of the scene for baking process
        /// </summary>
        /// <returns></returns>
        void PreparationStage() {
            displayCollection = new Dictionary<Hex, MeshRenderer>();
            currentChunk = dirtyChunks[0];

            Chunk c = currentChunk;
            Rect r = c.GetRect();
            Vector2 center = r.center;

            List<Hex> hexes = c.hexesCovered.Values.ToList();
            hexes = hexes.OrderBy(x => x.orderPosition).ToList();

            foreach (KeyValuePair<Vector3i, Hex> pair in c.hexesCovered) {
                MeshRenderer mr = GetFreeRenderer();
                Hex h = pair.Value;
                Vector2 pos = h.GetWorldPosition() - center;

                int index = hexes.IndexOf(h);

                mr.transform.localScale = Vector3.one * Hex.hexTextureScale * 2f;
                mr.transform.localPosition = new Vector3(pos.x, pos.y, 20 + index * 5);
                mr.transform.localRotation = Quaternion.Euler(0.0f, 0.0f, h.rotationAngle);

                mr.material.mainTexture = h.terrainType.diffuse;
                displayCollection[h] = mr;

                //add hex outlines behind camera for later use
                MeshRenderer outlineMr = GetFreeOutlineRenderer();
                outlineMr.transform.localPosition = new Vector3(pos.x, pos.y, -5);
            }

            PrepareRivers(new Vector3(-center.x, -center.y, 10));
        }

        /// <summary>
        /// Functionality which places sea hexes to the top and scales them up. This way they can produce beaches easier
        /// </summary>
        /// <returns></returns>
        void ReorderHexesPlacingWaterOnTop() {
            foreach (MeshRenderer mr in quadCollection) {
                mr.gameObject.SetActive(false);
            }

            Chunk c = currentChunk;
            Rect r = c.GetRect();
            Vector2 center = r.center;

            //we want now sea hexes to be on top of all other hexes. No changes otherwise.
            //for this purpose we will split hexes into two lists. sort them separately and then merge
            List<Hex> hexes = c.hexesCovered.Values.ToList();
            List<Hex> seaHexes = hexes.FindAll(o => o.terrainType.source.seaType);
            List<Hex> nonSeaHexes = hexes.FindAll(o => !o.terrainType.source.seaType);

            seaHexes = seaHexes.OrderBy(x => x.orderPosition).ToList();
            nonSeaHexes = nonSeaHexes.OrderBy(x => x.orderPosition).ToList();

            hexes.Clear();
            hexes.AddRange(seaHexes);
            hexes.AddRange(nonSeaHexes);

            foreach (KeyValuePair<Vector3i, Hex> pair in c.hexesCovered) {
                MeshRenderer mr = GetFreeRenderer();
                Hex h = pair.Value;
                Vector2 pos = h.GetWorldPosition() - center;

                int index = hexes.IndexOf(h);

                if (h.terrainType.source.seaType) {
                    //expand area covered by water hex so that it can draw better beaches
                    mr.transform.localScale = Vector3.one * Hex.hexTextureScale * 2f * 1.25f;
                }

                mr.transform.localPosition = new Vector3(pos.x, pos.y, 20 + index * 5);
                mr.transform.localRotation = Quaternion.Euler(0.0f, 0.0f, h.rotationAngle);

                displayCollection[h] = mr;
            }
        }

        /// <summary>
        /// sets river meshes in place for baking process
        /// </summary>
        /// <param name="bakingOffset"></param>
        /// <returns></returns>
        void PrepareRivers(Vector3 bakingOffset) {
            //prepare smoothener a bit before river 
            GameObject root = GameObject.Find("RiverSmoothener");
            root.transform.localPosition = bakingOffset + Vector3.forward * 2;

            root = GameObject.Find("RiverRoot");
            root.transform.localPosition = bakingOffset;
        }

        /// <summary>
        /// Preparation and render of the global mixer texture containing summary of the territorial fights between hexes
        /// </summary>
        /// <returns></returns>
        void BakingMixerStage() {
            //Hexes
            foreach (KeyValuePair<Hex, MeshRenderer> pair in displayCollection) {
                if (pair.Value.material != null) { GameObject.Destroy(pair.Value.material); }

                pair.Value.material = mixerMaterial;
                Material m = pair.Value.material;
                m.name = "mixerMaterialAT" + currentChunk.position + "FOR" + pair.Key.position;
                m.mainTexture = pair.Key.terrainType.mixer;
            }

            //river shape background
            foreach (MeshRenderer river in riverSmoothenerSections) {
                if (river.material != null) { GameObject.Destroy(river.material); }

                river.material = mixerMaterial;
                Material m = river.material;
                m.name = "mixerMaterialAT" + currentChunk.position + "FORriverSmooth" + riverSmoothenerSections.IndexOf(river);
                m.SetFloat("_Centralization", 0.0f);
                m.mainTexture = riverSmoothenerTexture;

            }

            //River 
            TerrainDefinition riverDef = TerrainDefinition.definitions.Find(o => o.source.mode == MHTerrain.Mode.IsRiverType);
            Texture riverMixer = riverDef.mixer;
            foreach (MeshRenderer river in riverSections) {
                if (river.material != null) { GameObject.Destroy(river.material); }

                river.material = mixerMaterial;

                Material m = river.material;
                m.name = "mixerMaterialAT" + currentChunk.position + "FORriver" + riverSmoothenerSections.IndexOf(river);
                m.SetFloat("_Centralization", 0.0f);
                m.mainTexture = riverMixer;
            }

            if (mixerRT != null) mixerRT.Release();

            mixerRT = RenderTargetManager.GetNewTexture(Chunk.TextureSize, Chunk.TextureSize, 24, RenderTextureFormat.ARGB32, RenderTextureReadWrite.Default, 1);
            bakingCamera.targetTexture = mixerRT;

            bakingCamera.Render();
            RenderTexture.active = null;
        }

        /// <summary>
        /// Preparation and render of the diffuse texture
        /// </summary>
        /// <returns></returns>
        void BakingDiffuseStage() {
            //Hexes
            foreach (KeyValuePair<Hex, MeshRenderer> pair in displayCollection) {
                if (pair.Value.material != null) { GameObject.Destroy(pair.Value.material); }

                pair.Value.material = diffuseMaterial;
                Material m = pair.Value.material;
                m.SetTexture("_MainTex", pair.Key.terrainType.diffuse);
                m.SetTexture("_Mixer", pair.Key.terrainType.mixer);
                m.SetTexture("_Height", pair.Key.terrainType.height);
                m.SetTexture("_GlobalMixer", mixerRT);
                m.SetTexture("_ShadowsAndHeight", shadowsAndHeightRT);
                m.SetFloat("_Sea", pair.Key.terrainType.source.seaType ? 1f : 0f);
                m.SetFloat("_Centralization", 1.0f);
            }

            //move river smoothener behind camera. It doesn't have diffuse to draw
            GameObject root = GameObject.Find("RiverSmoothener");
            root.transform.localPosition = root.transform.localPosition - Vector3.forward * 20;

            //River
            TerrainDefinition riverDef = TerrainDefinition.definitions.Find(o => o.source.mode == MHTerrain.Mode.IsRiverType);
            Texture riverDiffuse = riverDef.diffuse;
            Texture riverMixer = riverDef.mixer;
            Texture riverHeight = riverDef.height;
            foreach (MeshRenderer river in riverSections) {
                if (river.material != null) { GameObject.Destroy(river.material); }

                river.material = diffuseMaterial;
                Material m = river.material;
                m.SetTexture("_MainTex", riverDiffuse);
                m.SetTexture("_Mixer", riverMixer);
                m.SetTexture("_Height", riverHeight);
                m.SetTexture("_GlobalMixer", mixerRT);
                m.SetTexture("_ShadowsAndHeight", shadowsAndHeightRT);
                m.SetFloat("_Sea", 0f);
                m.SetFloat("_Centralization", 0.0f);
            }

            if (diffuseRT != null) diffuseRT.Release();

            diffuseRT = RenderTargetManager.GetNewTexture(Chunk.TextureSize, Chunk.TextureSize, 24, RenderTextureFormat.ARGB32, RenderTextureReadWrite.Default, 1);
            diffuseRT.wrapMode = TextureWrapMode.Clamp;
            bakingCamera.targetTexture = diffuseRT;

            bakingCamera.Render();
        }

        /// <summary>
        /// Preparation and render of the height texture
        /// </summary>
        /// <returns></returns>
        void BakingHeightStage() {
            //Hexes
            foreach (KeyValuePair<Hex, MeshRenderer> pair in displayCollection) {
                if (pair.Value.material != null) { GameObject.Destroy(pair.Value.material); }

                pair.Value.material = heightMaterial;
                Material m = pair.Value.material;
                m.SetTexture("_MainTex", pair.Key.terrainType.height);
                m.SetTexture("_Mixer", pair.Key.terrainType.mixer);
                m.SetTexture("_GlobalMixer", mixerRT);
            }

            //river
            TerrainDefinition riverDef = TerrainDefinition.definitions.Find(o => o.source.mode == MHTerrain.Mode.IsRiverType);
            Texture riverHeight = riverDef.height;
            Texture riverMixer = riverDef.mixer;
            foreach (MeshRenderer river in riverSections) {
                if (river.material != null) { GameObject.Destroy(river.material); }

                river.material = riverHeightMaterial;
                Material m = river.material;
                m.SetFloat("_Centralization", 0.0f);
                m.SetTexture("_MainTex", riverHeight);
                m.SetTexture("_Mixer", riverMixer);
                m.SetTexture("_GlobalMixer", mixerRT);
            }

            //Smoothener will neutralize a bit area where river would be located to avoid artefacts as much as possible
            foreach (MeshRenderer river in riverSmoothenerSections) {
                if (river.material != null) { GameObject.Destroy(river.material); }

                river.material = riverSmoothenerMaterial;
                Material m = river.material;
                m.SetTexture("_MainTex", riverSmoothenerTexture);
            }


            if (heightRT != null) heightRT.Release();

            heightRT = RenderTargetManager.GetNewTexture(Chunk.TextureSize >> 1, Chunk.TextureSize >> 1, 24, RenderTextureFormat.ARGB32, RenderTextureReadWrite.Default, 1);
            heightRT.wrapMode = TextureWrapMode.Clamp;
            bakingCamera.targetTexture = heightRT;

            bakingCamera.Render();
        }


        /// <summary>
        /// Shortcut to do another render with the same settings (camera settings my be different, but scene is the same)
        /// </summary>
        /// <param name="target"></param>
        /// <param name="downscale"></param>
        /// <returns></returns>
        void BakeTo(ref RenderTexture target, int downscale) {
            if (target != null) target.Release();

            target = RenderTargetManager.GetNewTexture(Chunk.TextureSize >> downscale, Chunk.TextureSize >> downscale, 24, RenderTextureFormat.ARGB32, RenderTextureReadWrite.Default, 1);
            target.wrapMode = TextureWrapMode.Clamp;
            bakingCamera.targetTexture = target;

            bakingCamera.Render();
        }

        /// <summary>
        /// Finds or instantiates quad together with its mesh renderer for hex textures
        /// </summary>
        /// <returns></returns>
        MeshRenderer GetFreeRenderer() {
            MeshRenderer mr = quadCollection.Find(o => o.gameObject.activeSelf == false);
            if (mr == null) {
                //create new instance, so we can use it to draw hex textures
                Transform t = quadBase.transform;
                GameObject go = GameObject.Instantiate(quadBase, t.position, t.rotation) as GameObject;
                go.transform.parent = t.parent;
                go.SetActive(true);

                mr = go.GetComponent<MeshRenderer>();
                quadCollection.Add(mr);
            } else {
                //reactivate it, so it can be used to draw hex textures
                mr.gameObject.SetActive(true);
            }

            return mr;
        }

        /// <summary>
        /// Finds or instantiates quad together with its mesh renderer for hex outline
        /// </summary>
        /// <returns></returns>
        MeshRenderer GetFreeOutlineRenderer() {
            MeshRenderer mr = hexOutlineCollection.Find(o => o.gameObject.activeSelf == false);
            if (mr == null) {
                //create new instance, so we can use it to draw hex textures
                Transform t = hexOutlineBase.transform;
                GameObject go = GameObject.Instantiate(hexOutlineBase, t.position, t.rotation) as GameObject;
                go.transform.parent = t.parent;
                go.transform.localScale = go.transform.localScale * Hex.hexRadius;
                go.SetActive(true);

                mr = go.GetComponent<MeshRenderer>();
                hexOutlineCollection.Add(mr);
            } else {
                //reactivate it, so it can be used to draw hex textures
                mr.gameObject.SetActive(true);
            }

            return mr;
        }

        /// <summary>
        /// Setting up and rendering using set of the heights textures producing shadows/light values and moving height to alpha channel for further conversion to Alpha8
        /// </summary>
        /// <param name="terrainHeight"></param>
        /// <param name="terrainHeightOff1"></param>
        /// <param name="terrainHeightOff2"></param>
        /// <returns></returns>
        RenderTexture ProduceShadowsAndHeightTexture(RenderTexture terrainHeight,
                                            RenderTexture terrainHeightOff1,
                                            RenderTexture terrainHeightOff2) {
            shadowsAndHeightMaterial.SetTexture("_Height", terrainHeight);
            shadowsAndHeightMaterial.SetTexture("_Height1", terrainHeightOff1);
            shadowsAndHeightMaterial.SetTexture("_Height2", terrainHeightOff2);


            RenderTexture rt = RenderTargetManager.GetNewTexture(terrainHeight.width, terrainHeight.height, 0, RenderTextureFormat.ARGB32);
            //simpler baking for older GPUs, in case they have problem with bilinear filtering in render targets

            terrainHeight.filterMode = FilterMode.Bilinear;
            terrainHeightOff1.filterMode = FilterMode.Bilinear;
            terrainHeightOff1.filterMode = FilterMode.Bilinear;
            rt.filterMode = FilterMode.Bilinear;

            Graphics.Blit(null, rt, shadowsAndHeightMaterial, 0);

            shadowsAndHeightMaterial.SetTexture("_Height", null);
            shadowsAndHeightMaterial.SetTexture("_Height1", null);
            shadowsAndHeightMaterial.SetTexture("_Height2", null);
            return rt;
        }


        /// <summary>
        /// Simple function which adds a bit of the blur to texture. used mostly by the height textures to avoid artifacts
        /// </summary>
        /// <param name="texture"></param>
        /// <param name="downSample"></param>
        /// <param name="size"></param>
        /// <param name="interations"></param>
        /// <returns></returns>
        void BlurTexture(RenderTexture texture, int downSample, int size, int interations) {
            float widthMod = 1.0f / (1.0f * (1 << downSample));

            Material material = new Material(blurMaterial);
            material.SetVector("_Parameter", new Vector4(size * widthMod, -size * widthMod, 0.0f, 0.0f));
            texture.filterMode = FilterMode.Bilinear;


            int rtW = texture.width >> downSample;
            int rtH = texture.height >> downSample;

            // downsample
            RenderTexture rt = RenderTargetManager.GetNewTexture(rtW, rtH, 0, texture.format);
            rt.filterMode = FilterMode.Bilinear;

            Graphics.Blit(texture, rt, material, 0);

            for (int i = 0; i < interations; i++) {
                float iterationOffs = (i * 1.0f);
                material.SetVector("_Parameter", new Vector4(size * widthMod + iterationOffs, -size * widthMod - iterationOffs, 0.0f, 0.0f));

                // vertical blur
                RenderTexture rt2 = RenderTargetManager.GetNewTexture(rtW, rtH, 0, texture.format);
                rt2.filterMode = FilterMode.Bilinear;

                Graphics.Blit(rt, rt2, material, 1);
                RenderTargetManager.ReleaseTexture(rt);
                rt = rt2;

                // horizontal blur
                rt2 = RenderTargetManager.GetNewTexture(rtW, rtH, 0, texture.format);
                rt2.filterMode = FilterMode.Bilinear;

                Graphics.Blit(rt, rt2, material, 2);
                RenderTargetManager.ReleaseTexture(rt);
                rt = rt2;
            }

            GameObject.Destroy(material);

            Graphics.Blit(rt, texture);

            RenderTargetManager.ReleaseTexture(rt);
        }

        // 烘焙区块国家颜色贴图
        private readonly int idCountriesColorData = Shader.PropertyToID("_CountriesColorData");
        private readonly int idChunkRect = Shader.PropertyToID("_ChunkRect");
        private readonly int idBakeTargetCountryColor = Shader.PropertyToID("_BakeTargetCountryColor");
        private readonly int idBakedCountriesColor = Shader.PropertyToID("_BakedCountriesColor");
        private readonly int idBakedCountriesColorBlur = Shader.PropertyToID("_BakedCountriesColorBlur");
        private readonly int idBakedCountriesColorBlurCombine = Shader.PropertyToID("_BakedCountriesColorBlurCombine");
        private int idBakeCountriesColorPass = -1;
        private int idBakeCountriesColorBlurPass = -1;
        private int idBakeCountriesColorBlurCombinePass = -1;
        public void BakeChunkCountriesColor(Chunk chunk, ref RenderTexture texColor, ref RenderTexture texBlur, in Texture2D data) {
            // 材质准备
            Material mat = chunk.chunkMaterial;
            Rect rect = chunk.GetRect();
            Vector4 rectV4 = new Vector4(rect.center.x, rect.center.y, rect.width, rect.height);
            if (idBakeCountriesColorPass < 0) {
                idBakeCountriesColorPass = mat.FindPass("BakeCountriesColorPass".ToUpper());
            }
            if (idBakeCountriesColorBlurPass < 0) {
                idBakeCountriesColorBlurPass = mat.FindPass("BakeCountriesColorBlurPass".ToUpper());
            }
            if (idBakeCountriesColorBlurCombinePass < 0) {
                idBakeCountriesColorBlurCombinePass = mat.FindPass("BakeCountriesColorBlurCombinePass".ToUpper());
            }
            mat.SetTexture(idCountriesColorData, data);
            mat.SetVector(idChunkRect, rectV4);

            // RT配置准备
            int size = bakeSize;
            int depth = 32;
            RenderTextureFormat format = RenderTextureFormat.ARGB32;

            // 烘焙颜色
            {
                RenderTexture rt0 = RenderTargetManager.GetNewTexture(size, size, depth, format);
                RenderTexture rt1 = RenderTargetManager.GetNewTexture(size, size, depth, format);

                mat.SetVector(idBakeTargetCountryColor, Color.clear);
                Graphics.Blit(rt0, rt1, mat, idBakeCountriesColorPass);

                //RenderTexture.active = rt1;
                //texColor.ReadPixels(new Rect(0, 0, size, size), 0, 0);
                //texColor.Apply();
                //RenderTexture.active = null;
                Graphics.Blit(rt1, texColor);

                rt1.Release();
                rt0.Release();
            }

            // 烘焙模糊效果, 用于制作边界线
            {
                RenderTexture rtBlur = RenderTargetManager.GetNewTexture(size, size, depth, format);
                HashSet<Color> countryColors = HexMarkers.GetCountryColors();

                mat.SetTexture(idBakedCountriesColorBlurCombine, rtBlur);
                foreach (Color targetColor in countryColors) {
                    // 0. 创建临时RT
                    RenderTexture rt0 = RenderTargetManager.GetNewTexture(size, size, depth, format);
                    RenderTexture rt1 = RenderTargetManager.GetNewTexture(size, size, depth, format);
                    RenderTexture rt2 = RenderTargetManager.GetNewTexture(size, size, depth, format);
                    RenderTexture rt3 = RenderTargetManager.GetNewTexture(size, size, depth, format);

                    // 1. 用区块的烘焙pass进行国家颜色贴图烘焙
                    mat.SetVector(idBakeTargetCountryColor, targetColor);
                    Graphics.Blit(rt0, rt1, mat, idBakeCountriesColorPass);

                    // 2. 应用临时贴图RT
                    Graphics.Blit(rt1, rt2);
                    mat.SetTexture(idBakedCountriesColor, rt2);

                    // 3. 模糊处理
                    BlurTexture(rt1, 1, 1, 6);
                    mat.SetTexture(idBakedCountriesColorBlur, rt1);
                    Graphics.Blit(rt1, rt0, mat, idBakeCountriesColorBlurPass);

                    // 4. 融合所有不同颜色模糊效果
                    mat.SetTexture(idBakedCountriesColorBlur, rt0);
                    Graphics.Blit(rt0, rt3, mat, idBakeCountriesColorBlurCombinePass);
                    Graphics.Blit(rt3, rtBlur);

                    // 5. 释放
                    rt3.Release();
                    rt2.Release();
                    rt1.Release();
                    rt0.Release();
                }
                mat.SetTexture(idBakedCountriesColorBlurCombine, null);

                // 最终应用贴图
                //RenderTexture.active = rtBlur;
                //texBlur.ReadPixels(new Rect(0, 0, size, size), 0, 0);
                //texBlur.Apply();
                //RenderTexture.active = null;
                Graphics.Blit(rtBlur, texBlur);

                // 释放
                rtBlur.Release();
            }

            mat.SetTexture(idBakedCountriesColor, texColor);
            mat.SetTexture(idBakedCountriesColorBlur, texBlur);
        }
    }
}
