# HyperOS 3 Enable AOD

一个面向 HyperOS 3 的 Root 模块：尝试为设备启用全屏 AOD，并在 AOD 场景允许 LTPO 屏幕降至 1Hz 刷新率。

## 工作原理

模块不会持久修改 `/product/etc/device_features` 中的原始设备配置。开机时，`post-fs-data.sh` 会：

1. 将当前系统的 `device_features` 目录完整复制到模块自己的临时副本；
2. 在每个 XML 中写入或将 `support_aod_fullscreen` 维护为 `true`；
3. 完成后将副本发布到模块的 `system/product/etc/device_features` 路径；
4. 在 Magisk 中交由 Magic Mount 自动挂载；在 KernelSU 中先尝试 OverlayFS，失败时回退为 bind mount。

因此，系统原始 XML 不会被写入；禁用或卸载模块并重启后，系统会恢复原状。

## 兼容性与测试状态

- 理论上可为所有支持该配置的设备动态注入 AOD 属性。
- 同时兼容 KernelSU 和 Magisk：KernelSU 使用 OverlayFS，并在失败时降级为 bind mount；Magisk 使用自身的 Magic Mount。
- 目前仅在 **小米 13 Ultra 的 KernelSU + bind mount** 路径上完成实际测试。
- OverlayFS、Magisk 以及其他机型尚未完成实机验证，欢迎反馈启动日志、挂载状态与效果。

## 警告

**请勿在不支持 LTPO 的屏幕上使用本模块的 1Hz 降频功能。** 这可能导致不可预料的显示、功耗或唤醒问题。

本模块只是在系统 OS 层补充功能开关。官方未适配的机型仍可能存在 HAL 底层兼容性问题，例如智能唤醒失效、屏幕熄灭后无法再次点亮等。

若要获得较完整的智能唤醒体验，通常需要搭配 [hyperos-full-aod-bridge](https://github.com/silverpoetry/hyperos-full-aod-bridge)。强烈推荐仔细阅读该项目：它不仅提供了有效的解决方案，也记录了详细的调试过程，很有学习价值。感谢作者。

## 日志与排障

每次启动时，模块会在自身目录生成 `boot.log`，记录准备、挂载及失败信息。KernelSU 下若 OverlayFS 不可用，日志中会显示其错误，并继续尝试 bind mount。

## 安装

从 Releases 下载 `HyperOS3EnableAOD.zip`，使用 Magisk 或 KernelSU 的模块安装界面安装，然后重启。
