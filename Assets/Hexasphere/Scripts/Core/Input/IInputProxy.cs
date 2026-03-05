using UnityEngine;

namespace HexasphereGrid {

    public interface IInputProxy {
        void Init();
        bool GetKey(KeyCode keyCode);
        bool GetKeyDown(KeyCode keyCode);
        bool GetMouseButton(int buttonIndex);
        bool GetMouseButtonDown(int buttonIndex);
        bool GetMouseButtonUp(int buttonIndex);
        bool GetButtonDown(string buttonName);
        bool GetButtonUp(string buttonName);
        float GetAxis(string axisName);
        Vector3 MousePosition { get; }
        bool TouchSupported { get; }
        int TouchCount { get; }
        Touch GetTouch(int touchIndex);
        int GetFingerIdFromTouch(int touchIndex);
        bool IsPointerOverUI();
        bool IsPointerOverUI(int fingerId);
    }
}
