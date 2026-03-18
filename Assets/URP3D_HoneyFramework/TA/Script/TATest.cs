using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class TATest : MonoBehaviour {
    [SerializeField] private GameObject plane;
    [SerializeField] private GameObject sphere;
    [SerializeField, Range(10.0f, 100.0f)] private float radius = 10.0f;
    [SerializeField] private bool playAnim = false;
    [SerializeField] private float spdAnim = 1.0f;
    [SerializeField] private float radiusAnimMin = 10.0f;
    [SerializeField] private float radiusAnimMax = 20.0f;

    private Material mat;

    private void Awake() {
        mat = plane.GetComponent<MeshRenderer>().material;
    }

    private void Update() {
        if (playAnim) {
            float t = (Mathf.Sin(Time.time * spdAnim) + 1.0f) * 0.5f;
            radius = Mathf.Lerp(radiusAnimMin, radiusAnimMax, t);
        }

        mat.SetFloat("_Radius", radius);
        sphere.transform.position = new Vector3(0.0f, -radius, 0.0f);
        sphere.transform.localScale = Vector3.one * radius * 2.0f;
    }

    private void OnDestroy() {
        mat.SetFloat("_Radius", 10.0f);
    }
}
