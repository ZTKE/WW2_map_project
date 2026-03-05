#if !ENABLE_INPUT_SYSTEM

using UnityEngine;
using UnityEngine.EventSystems;

namespace HexasphereGrid {

    public class DefaultInputSystem : IInputProxy {

        public virtual void Init() { }

        public virtual Vector3 MousePosition => Input.mousePosition;

        public virtual bool TouchSupported => Input.touchSupported;

        public virtual int TouchCount => Input.touchCount;

        public virtual bool GetKey(KeyCode keyCode) {
            return Input.GetKey(keyCode);
        }

        public virtual bool GetKeyDown(KeyCode keyCode) {
            return Input.GetKeyDown(keyCode);
        }

        public virtual bool GetMouseButton(int buttonIndex) {
            return Input.GetMouseButton(buttonIndex);
        }

        public virtual bool GetMouseButtonDown(int buttonIndex) {
            return Input.GetMouseButtonDown(buttonIndex);
        }

        public virtual bool GetMouseButtonUp(int buttonIndex) {
            return Input.GetMouseButtonUp(buttonIndex);
        }

        public virtual bool GetButtonDown(string buttonName) {
            return Input.GetButtonDown(buttonName);
        }

        public virtual bool GetButtonUp(string buttonName) {
            return Input.GetButtonUp(buttonName);
        }

        public virtual float GetAxis(string axisName) {
            return Input.GetAxis(axisName);
        }

        public virtual Touch GetTouch(int touchIndex) {
            return Input.GetTouch(touchIndex);
        }

        public virtual int GetFingerIdFromTouch(int touchIndex) {
            return Input.GetTouch(touchIndex).fingerId;
        }

        public virtual bool IsPointerOverUI() {
            if (EventSystem.current == null) return false;
            return EventSystem.current.IsPointerOverGameObject(-1);
        }

        public virtual bool IsPointerOverUI(int fingerId) {
            if (EventSystem.current == null) return false;
            return EventSystem.current.IsPointerOverGameObject(fingerId);
        }
    }
}

#endif
