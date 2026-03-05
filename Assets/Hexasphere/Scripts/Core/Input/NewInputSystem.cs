#if ENABLE_INPUT_SYSTEM

using System.Collections.Generic;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.Controls;
using UnityEngine.InputSystem.UI;
using EnhancedTouch = UnityEngine.InputSystem.EnhancedTouch;

namespace HexasphereGrid {

    public class NewInputSystem : IInputProxy {

        readonly List<RaycastResult> pointer_raycastResults = new List<RaycastResult>();

        public virtual void Init() {
            EnhancedTouch.EnhancedTouchSupport.Enable();
            SetupEventSystem();
        }

        void SetupEventSystem() {
            var eventSystem = EventSystem.current;
            if (eventSystem == null) return;
            var standaloneModule = eventSystem.GetComponent<StandaloneInputModule>();
            if (standaloneModule != null) {
                Object.Destroy(standaloneModule);
                if (eventSystem.GetComponent<InputSystemUIInputModule>() == null) {
                    eventSystem.gameObject.AddComponent<InputSystemUIInputModule>();
                }
            }
        }

        public virtual Vector3 MousePosition {
            get {
                if (Application.isMobilePlatform) {
                    if (TouchCount > 0) {
                        return EnhancedTouch.Touch.activeFingers[0].currentTouch.screenPosition;
                    }
                    return Vector3.zero;
                }
                var mouse = Mouse.current;
                if (mouse == null) return Vector3.zero;
                return mouse.position.ReadValue();
            }
        }

        public virtual bool TouchSupported => Touchscreen.current != null;

        public virtual int TouchCount => EnhancedTouch.Touch.activeTouches.Count;

        public virtual bool GetKey(KeyCode keyCode) {
            var keyboard = Keyboard.current;
            if (keyboard == null) return false;
            var control = GetKeyControl(keyboard, keyCode);
            if (control == null) return false;
            return control.isPressed;
        }

        public virtual bool GetKeyDown(KeyCode keyCode) {
            var keyboard = Keyboard.current;
            if (keyboard == null) return false;
            var control = GetKeyControl(keyboard, keyCode);
            if (control == null) return false;
            return control.wasPressedThisFrame;
        }

        public virtual bool GetMouseButton(int buttonIndex) {
            switch (buttonIndex) {
                case 1: return !Application.isMobilePlatform && Mouse.current != null && Mouse.current.rightButton.isPressed;
                case 2: return !Application.isMobilePlatform && Mouse.current != null && Mouse.current.middleButton.isPressed;
                default:
                    if (Application.isMobilePlatform) {
                        return TouchCount > 0 && EnhancedTouch.Touch.activeTouches[0].isInProgress;
                    }
                    return Mouse.current != null && Mouse.current.leftButton.isPressed;
            }
        }

        public virtual bool GetMouseButtonDown(int buttonIndex) {
            switch (buttonIndex) {
                case 1: return !Application.isMobilePlatform && Mouse.current != null && Mouse.current.rightButton.wasPressedThisFrame;
                case 2: return !Application.isMobilePlatform && Mouse.current != null && Mouse.current.middleButton.wasPressedThisFrame;
                default:
                    if (Application.isMobilePlatform) {
                        if (TouchCount > 0) {
                            return EnhancedTouch.Touch.activeTouches[0].phase == UnityEngine.InputSystem.TouchPhase.Began;
                        }
                        return false;
                    }
                    return Mouse.current != null && Mouse.current.leftButton.wasPressedThisFrame;
            }
        }

        public virtual bool GetMouseButtonUp(int buttonIndex) {
            switch (buttonIndex) {
                case 1: return !Application.isMobilePlatform && Mouse.current != null && Mouse.current.rightButton.wasReleasedThisFrame;
                case 2: return !Application.isMobilePlatform && Mouse.current != null && Mouse.current.middleButton.wasReleasedThisFrame;
                default:
                    if (Application.isMobilePlatform) {
                        return TouchCount > 0 && EnhancedTouch.Touch.activeTouches[0].phase == UnityEngine.InputSystem.TouchPhase.Ended;
                    }
                    return Mouse.current != null && Mouse.current.leftButton.wasReleasedThisFrame;
            }
        }

        public virtual bool GetButtonDown(string buttonName) {
            var mouse = Mouse.current;
            var keyboard = Keyboard.current;
            switch (buttonName) {
                case "Fire1":
                    return mouse != null && mouse.leftButton.wasPressedThisFrame;
                case "Fire2":
                    return mouse != null && mouse.rightButton.wasPressedThisFrame;
                case "Jump":
                    return keyboard != null && keyboard.spaceKey.wasPressedThisFrame;
                default:
                    return false;
            }
        }

        public virtual bool GetButtonUp(string buttonName) {
            var mouse = Mouse.current;
            var keyboard = Keyboard.current;
            switch (buttonName) {
                case "Fire1":
                    return mouse != null && mouse.leftButton.wasReleasedThisFrame;
                case "Fire2":
                    return mouse != null && mouse.rightButton.wasReleasedThisFrame;
                case "Jump":
                    return keyboard != null && keyboard.spaceKey.wasReleasedThisFrame;
                default:
                    return false;
            }
        }

        public virtual float GetAxis(string axisName) {
            var mouse = Mouse.current;
            switch (axisName) {
                case "Mouse ScrollWheel":
                    if (mouse == null) return 0f;
                    return mouse.scroll.y.ReadValue() / 120f;
                default:
                    return 0f;
            }
        }

        public virtual Touch GetTouch(int touchIndex) {
            if (touchIndex >= EnhancedTouch.Touch.activeTouches.Count) return default;
            var touch = EnhancedTouch.Touch.activeTouches[touchIndex];
            return new Touch {
                fingerId = touch.finger.index,
                position = touch.screenPosition,
                deltaPosition = touch.delta,
                phase = ConvertTouchPhase(touch.phase)
            };
        }

        public virtual int GetFingerIdFromTouch(int touchIndex) {
            if (touchIndex >= EnhancedTouch.Touch.activeTouches.Count) return -1;
            return EnhancedTouch.Touch.activeTouches[touchIndex].finger.index;
        }

        public virtual bool IsPointerOverUI() {
            if (EventSystem.current == null) return false;
            var eventData = new PointerEventData(EventSystem.current) { position = MousePosition };
            EventSystem.current.RaycastAll(eventData, pointer_raycastResults);
            int resultsCount = pointer_raycastResults.Count;
            for (int k = 0; k < resultsCount; k++) {
                if (pointer_raycastResults[k].gameObject.layer == 5 && pointer_raycastResults[k].gameObject.GetComponent<RectTransform>() != null)
                    return true;
            }
            return false;
        }

        public virtual bool IsPointerOverUI(int fingerId) {
            return IsPointerOverUI();
        }

        static KeyControl GetKeyControl(Keyboard keyboard, KeyCode keyCode) {
            switch (keyCode) {
                case KeyCode.A: return keyboard.aKey;
                case KeyCode.D: return keyboard.dKey;
                case KeyCode.G: return keyboard.gKey;
                case KeyCode.S: return keyboard.sKey;
                case KeyCode.W: return keyboard.wKey;
                case KeyCode.LeftAlt: return keyboard.leftAltKey;
                case KeyCode.RightAlt: return keyboard.rightAltKey;
                case KeyCode.LeftShift: return keyboard.leftShiftKey;
                case KeyCode.RightShift: return keyboard.rightShiftKey;
                case KeyCode.Space: return keyboard.spaceKey;
                case KeyCode.Escape: return keyboard.escapeKey;
                default: return null;
            }
        }

        static UnityEngine.TouchPhase ConvertTouchPhase(UnityEngine.InputSystem.TouchPhase phase) {
            switch (phase) {
                case UnityEngine.InputSystem.TouchPhase.Began: return UnityEngine.TouchPhase.Began;
                case UnityEngine.InputSystem.TouchPhase.Moved: return UnityEngine.TouchPhase.Moved;
                case UnityEngine.InputSystem.TouchPhase.Stationary: return UnityEngine.TouchPhase.Stationary;
                case UnityEngine.InputSystem.TouchPhase.Ended: return UnityEngine.TouchPhase.Ended;
                case UnityEngine.InputSystem.TouchPhase.Canceled: return UnityEngine.TouchPhase.Canceled;
                default: return UnityEngine.TouchPhase.Canceled;
            }
        }
    }
}

#endif
