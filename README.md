# HyperOS 3 Enable AOD

一个面向 HyperOS 3 的 Root 模块：尝试启用全屏 AOD，并让支持 LTPO 的屏幕可在 AOD 场景降至 1Hz 刷新率。

> 本模块并非原创功能实现，而是基于社区已有方案进行整理、打包与发布，方便安装和测试。

## 工作原理

模块不会持久修改 `/product/etc/device_features` 中的原始设备配置。开机时，`post-fs-data.sh` 会：

1. 将当前系统的 `device_features` 目录完整复制到模块自己的临时副本；
2. 在每个 XML 中写入或将 `support_aod_fullscreen` 维护为 `true`；
3. 完成后将副本发布到模块的 `system/product/etc/device_features` 路径；
4. 在 Magisk 中交由 Magic Mount 自动挂载；在 KernelSU 中先尝试只读 OverlayFS（先将模块副本复制到 `/dev` 的 tmpfs，再与系统原目录组成两个 lowerdir），失败时回退为 bind mount。

因此，系统原始 XML 不会被写入；禁用或卸载模块并重启后，系统会恢复原状。

## 支持范围与测试状态

- 理论上可为支持该配置的机型动态注入 AOD 属性。
- 同时面向 KernelSU 和 Magisk：KernelSU 先尝试只读 OverlayFS，失败时回退为 bind mount；Magisk 使用自身的 Magic Mount。
- 已在 **小米 13 Ultra 的 KernelSU** 环境验证只读 OverlayFS 挂载及 XML 开关注入，bind mount 回退也已验证。
- 实际 AOD 显示效果、禁用/卸载后的恢复、Magisk 与其他机型仍需进一步验证；如有问题，请附上模块 `boot.log`、挂载状态和机型/系统版本。

## 警告

**请勿在不支持 LTPO 的屏幕上使用本模块的 1Hz 降频功能。** 这可能导致不可预料的显示、功耗或唤醒问题。

本模块只是在系统 OS 层补充功能开关。对官方未适配的机型，仍可能存在 HAL 底层兼容性问题，例如智能唤醒失效、屏幕熄灭后无法再次点亮等。

## 完整智能唤醒体验：强烈推荐配套项目

本模块负责在 **OS 层** 打开 AOD 能力；但对官方没有完整适配的机型，仅有这个开关通常不足以解决 HAL 与智能唤醒链路的问题。

强烈推荐搭配 [silverpoetry/hyperos-full-aod-bridge](https://github.com/silverpoetry/hyperos-full-aod-bridge) 使用，以获得更完整的智能唤醒体验。这个项目不但提供了有效的解决方案，也完整记录了排查、验证与调试过程，极具学习价值。感谢原作者的工作。

## OverlayFS 底层目录兼容性

部分 Android `/data` 文件系统的 dentry 操作不被 OverlayFS 接受，即使双 lowerdir 参数正确也会返回 `EINVAL`。KernelSU 路径因此将修改后的目录复制到现有 `/dev` tmpfs 的独立临时目录，避免直接把 `/data` 副本作为 lowerdir，不额外挂载 tmpfs。成功后保留这份内存副本供 OverlayFS 使用，重启自动释放；失败时删除本次临时目录并回退 bind。

## 日志与排障

每次启动时，模块会在自身目录生成 `boot.log`，记录准备、挂载及失败信息。KernelSU 下 OverlayFS 成功时记录 `mount method: overlayfs`；失败时记录错误并回退，bind 成功时记录 `mount method: bind`。

## 安装

从 Releases 下载 `HyperOS3EnableAOD.zip`，使用 Magisk 或 KernelSU 的模块安装界面安装，然后重启。
