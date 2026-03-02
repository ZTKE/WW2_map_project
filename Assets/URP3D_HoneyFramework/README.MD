# Honey Framework URP改版

> 版本：v1.0.0
>
> 修改日期：2026.03.02
>
> 开发者：Numbfish

## 一、Config

首先添加4个Layer，从第8个Layer开始命名：

```
User Layer 8: Trees
User Layer 9: Terrain
User Layer 10: Baking
User Layer 11: Actors
```

然后打开Project Settings，找到Player选项，修改里面的Other Settings/Rendering/Color Space为Gamma空间

## 二、Todo

按优先级从高到低排列：

- 国家区域高亮描边（需要花点时间）
- 水渲染优化，目前没有和主相机画面的深度融合得很好
- Gamma空间修改为线性空间，需要调整烘焙代码

## 三、Change Log

### 2026.03.02_v1.0.0

- 完成Built-in到URP的转换，包括修改Shader和修改相机堆叠逻辑
- 确认了渲染差异问题是颜色空间导致的，目前暂时先用Gamma空间