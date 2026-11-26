# 校园地图渲染说明

校园地图画布使用纯 Flutter 原生渲染（`CustomPainter` + 双层 GPU `ui.Image` 缓存），
不再依赖 `WKWebView` / Android `WebView` PlatformView：

- **全图基础纹理**：切换校区时一次性将整张离线 SVG 烘焙为 GPU 纹理（长边上限 2560px），拖动、惯性与缩放在任意位置都不会出现缓存断层或空白边缘。
- **放大清晰纹理**：放大倍率超过基础纹理密度且手势停稳 200ms 后，按视口包围盒裁剪异步烘焙当前视口及 8% 周边区域的清晰纹理（长边上限 2400px）；手势与惯性期间零重栅格化，在 iOS ProMotion 120Hz 与 Android 高刷屏上均可满帧渲染。
- **矢量叠加与命中**：选中建筑高亮、点位标记与定位蓝点直接在同一次 `CustomPainter` 矢量绘制；点击命中直接基于建筑世界坐标 `Path` 判断。
- **手势与惯性**：单指拖动以最近 80 ms 的输入估计速度，松手后通过 Flutter `Ticker` 按时间积分减速；系统开启“减少动态效果”时禁用惯性并立即完成聚焦。

## 回归测试

```sh
flutter test test/features/campus_map/ test/data/repositories/campus_map_test.dart
```
