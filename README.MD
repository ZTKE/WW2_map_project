# Honey Framework URP改版

> 版本：v1.1.0
>
> 修改日期：2026.03.04
>
> 开发者：Numbfish

## 一、Config

### 1.1 Layer

首先添加4个Layer，从第8个Layer开始命名：

```
User Layer 8: Trees
User Layer 9: Terrain
User Layer 10: Baking
User Layer 11: Actors
```

### 1.2 Gamma

然后打开Project Settings，找到Player选项，修改里面的Other Settings/Rendering/Color Space为Gamma空间

关于Gamma空间与线性空间的知识，可以看这两个网站：

1. https://zhuanlan.zhihu.com/p/423301746
2. https://docs.unity3d.com/cn/current/Manual/differences-linear-gamma-color-space.html

### 1.3 Depth texture

水面渲染需要打开深度图渲染选项，默认的UPR工程里面有一个叫URP-HighFidelity的渲染管线配置文件，勾选其Rendering/Depth Texture选项即可

### 1.4 Renderer feature

水面渲染还需要额外添加一个Renderer feature来借助主相机的深度贴图渲染，默认的URP工程里面有一个叫URP-HighFidelity-Renderer的渲染管线配置文件，点击最下面的Add Renderer Feature按钮，添加一个Depth Copy Feature即可。然后运行时想看到水面，就把Water相机打开

### 1.5 MSAA

MSAA是一个画面抗锯齿技术，但是加上这个MSAA之后渲染代码会比较难写，目前暂时需要关闭。默认的UPR工程里面有一个叫URP-HighFidelity的渲染管线配置文件，将Quality/Anit Aliasing (MSAA)修改为Disabled即可关闭

## 二、Todo

按优先级从高到低排列：

- 国家区域高亮描边（需要花点时间）
- 水渲染优化，目前没有和主相机画面的深度融合得很好
- Gamma空间修改为线性空间，需要调整烘焙代码

## 三、Change Log

### 2026.03.04_v1.1.0

- 完成水渲染效果移植，需要添加一个叫DepthCopyFeature的Renderer feature来获取主相机的深度贴图，才能完成水的渲染
- 目前暂时不支持MSAA

### 2026.03.02_v1.0.0

- 完成Built-in到URP的转换，包括修改Shader和修改相机堆叠逻辑
- 确认了渲染差异问题是颜色空间导致的，目前暂时先用Gamma空间