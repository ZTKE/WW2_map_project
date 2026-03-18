# Honey Framework URP改版

> 版本：v1.2.1
>
> 修改日期：2026.03.17
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

- 球形地形，并兼容必须要的五边形地块
  
- Gamma空间修改为线性空间，需要调整烘焙代码

## 三、Change Log

### 2026.03.09_v1.2.1

- 优化Honey Framework基础结构代码（部分static改为const）

### 2026.03.09_v1.2.0

- 完成国家颜色区域渲染性能优化

### 2026.03.09_v1.1.5

- 初步完成国家颜色区域渲染
- 目前还有一些切换区块时的渲染问题需要解决，以及需要做性能优化

### 2026.03.04_v1.1.0

- 完成水渲染效果移植，需要添加一个叫DepthCopyFeature的Renderer feature来获取主相机的深度贴图，才能完成水的渲染
- 目前暂时不支持MSAA

### 2026.03.02_v1.0.0

- 完成Built-in到URP的转换，包括修改Shader和修改相机堆叠逻辑
- 确认了渲染差异问题是颜色空间导致的，目前暂时先用Gamma空间

---

## 附录一、Honey Framework标记贴图原理

在Shader中，有3个与标记有关的属性`_MarkersGraphic`，`_MarkersPositionData`，`_MarkerSettings`

首先看`_MarkerSettings`，默认值为`(8, 8, 64, 2)`，其`xyzw`分别的含义为：

- `x`：marker graphic count width
  - `_MarkersGraphic`标记贴图表横向个数
- `y`：marker graphic count height
  - `_MarkersGraphic`标记贴图表纵向个数
- `z`：marker data width hex count, <- expected to be square for height
  - `_MarkersPositionData`标记数据RT贴图像素宽度（默认高度等于宽度），这张RT将记录整个世界地图的标记数据，是所有区块共享的数据，其像素坐标对应了六边形坐标的`x`和`y`，如果六边形坐标为负数，则反向查找坐标（见函数`HexMarkers.SetMarkerType(...)`）
  - **也就是说，地图格子数量有多少，这张数据图就应该扩展到足够大的尺寸才行**
- `w`：marker hex data size, <- number of following pixels of data for each hex
  - `_MarkersPositionData`标记数据RT贴图像素宽度乘倍，例如原先是记录64×64的地图坐标数据，现在每个地块需要标记的种类比较多，需要扩展到128×128，每2个像素点记录一个坐标数据
  - **也就是说，如果地块标记的种类越多，这张数据图就应该相应扩展到足够大的乘倍才行**

## 附录二、Honey Framework世界贴图烘焙原理

具体看`WorldOven`代码，在`Baking()`协程内按顺序加工渲染出最终贴图（具体加工流程说明：todo...）

根据原版插件原理，我也做了一个烘焙国家区域颜色的函数`CmdBufBakeChunkCountriesColor()`，具体烘焙步骤为：

1. 烘焙纯色六边形
2. 将纯色六边形按颜色不同单独分开烘焙对应的模糊贴图
3. 将所有模糊贴图合并为单张图

然后在渲染时，就可以使用合并后的模糊贴图来计算边界线了

在性能优化上，使用了`CommandBuffer`来执行渲染，能无阻塞地完成烘焙渲染任务

## 附录三、平坦世界六边形坐标系

在Honey Framework中，首先确定坐标系结构，见`Hex`，坐标为3个int值（使用`Vector3i`），xyz对应3个方向：

```
      -=| X |=-    To East
     \    0    /
      \_______/
  -1  /       \    1 
 ____/    0    \______
     \         /      
  -1  \_______/    1
      /       \
     /    0    \

      -=| Y |=-      To North-West
     \    1    /
      \_______/
   1  /       \    0
 ____/    0    \______ 
     \         /      
   0  \_______/   -1
      /       \
     /   -1    \

      -=| Z |=-      To South-West
     \   -1    /
      \_______/
   0  /       \   -1
 ____/    0    \______
     \         /
   1  \_______/    0
      /       \
     /    1    \
```

```
       \ (0,1,-1)/       \ (2,0,-2)/
(-1,1,0)\_______/ (1,0,-1)\_______/ (3,-1,-2)
        /       \         /       \
   ____/ (0,0,0) \_______/(2,-1,-1)\_______
       \         /       \         /
(-1,0,1)\_______/ (1,-1,0)\_______/ (3,-2,-1)
        /       \         /       \
       / (0,-1,1)\       / (2,-2,0)\
```

即x轴对应的是(1, 0)方向，y轴对应x轴旋转120度为(-0.5, 0.8660254)，z轴对应x轴旋转240度为(-0.5, -0.8660254)。计算公式：[六边形坐标旋转 | Desmos](https://www.desmos.com/calculator/kcscgeviip?lang=zh-CN)

还可以发现六边形坐标xyz满足三者之和为0的特性

有了基础的数据结构后，接下来是准备相关的坐标转换计算，具体见`HexCoordinates`。先看世界坐标转六边形坐标函数`HexCoordinates.WorldToHex()`，`Hex.hexRadius`为六边形中心往右到边角的长度，即为1，六边形边长也是1，所以六边形x坐标为世界坐标x的2/3，同理推导出y和z

```C#
static public Vector3 WorldToHex(Vector3 pos) {
    const float TWO_THIRD = 2.0f / 3.0f;
    const float ONE_THIRD = 1.0f / 3.0f;
    const float SQRT_3 = 1.732050807568877f;
    const float COMPONENT = ONE_THIRD * SQRT_3;
    float x = TWO_THIRD * pos.x / Hex.hexRadius;
    float y = (COMPONENT * pos.z - ONE_THIRD * pos.x) / Hex.hexRadius;
    float z = -x - y;
    return new Vector3(x, y, z);
}
```

然后看`HexCoordinates.HexToWorld()`，其中`Hex.GetDir...()`对应3个基础方向向量（[六边形坐标旋转 | Desmos](https://www.desmos.com/calculator/kcscgeviip?lang=zh-CN)）

```C#
static public Vector2 HexToWorld(Vector3i pos) {
    Vector2 worldPos = Hex.GetDirX() * pos.x + Hex.GetDirY() * pos.y + Hex.GetDirZ() * pos.z;
    return worldPos;
}
```

如果要计算两个六边形距离，则使用`HexCoordinates.HexDistance()`，这里的距离相当于计算从`hexA`扩大多少半径能碰到`hexB`

```C#
static public int HexDistance(Vector3i hexA, Vector3i hexB) {
    return Mathf.Max(Mathf.Abs(hexB.x - hexA.x), Mathf.Abs(hexB.y - hexA.y), Mathf.Abs(hexB.z - hexA.z));
}
```

## 附录四、球形世界六边形坐标系

todo...

## 附录五、平坦世界转球形世界坐标系

todo...
