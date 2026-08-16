#!/system/bin/sh
# 使用 Android 启动阶段自带的 Shell 执行本脚本。

# 从脚本自身路径得到模块根目录，不假定模块安装在固定位置。
MODDIR="${0%/*}"
# 系统原始机型配置目录；只读取，绝不直接写入。
FEATURE_DIR="/product/etc/device_features"
# 模块内的最终副本；Magisk 会自动挂载它，KSU 会由本脚本 bind 挂载它。
TARGET_DIR="$MODDIR/system/product/etc/device_features"
# 先在独立暂存目录完成全部修改，避免发布半成品。
STAGE_DIR="$MODDIR/.device_features.new"

# 统一输出带模块名称的启动日志。
log() {
    echo "[HyperOS3EnableAOD] $*"
}

# 发生错误时只清理模块自己的暂存目录，然后以失败状态结束。
fail() {
    log "ERROR: $*"
    rm -rf "$STAGE_DIR"
    exit 1
}

# 系统原始目录不存在时停止，不猜测其他系统路径。
[ -d "$FEATURE_DIR" ] || fail "missing source directory: $FEATURE_DIR"

# 删除上次生成的副本，避免本轮准备失败时保留旧配置。
rm -rf "$TARGET_DIR"
# 删除上次异常留下的暂存目录，保证本轮从干净状态开始。
rm -rf "$STAGE_DIR"
# 创建本轮暂存目录。
mkdir -p "$STAGE_DIR" || fail "cannot create staging directory"
# 完整复制原目录，包括非 XML 文件；修改只会发生在这份副本中。
cp -af "$FEATURE_DIR/." "$STAGE_DIR/" || fail "cannot copy device_features"

# 记录处理到的 XML 数量，避免把空目录当作成功。
xml_count=0
# 逐个处理暂存副本中的机型 XML；正常情况下目录中只有当前机型的一个 XML。
for xml_file in "$STAGE_DIR"/*.xml; do
    # 没有匹配到 XML 时跳过通配符本身。
    [ -f "$xml_file" ] || continue
    # 找到一个 XML 后计数。
    xml_count=$((xml_count + 1))

    # 已有该开关时，只把其标准 true/false 值统一改为 true。
    if grep -q 'support_aod_fullscreen' "$xml_file"; then
        sed -i 's|^[[:space:]]*<bool[[:space:]]\\+name="support_aod_fullscreen">\\(true\\|false\\)</bool>[[:space:]]*$|    <bool name="support_aod_fullscreen">true</bool>|' "$xml_file" || fail "cannot update AOD flag"
    # 原文件没有该开关时，在 features 的闭合标签前新增一行。
    else
        sed -i '/^[[:space:]]*<\\/features>[[:space:]]*$/i\\
    <bool name="support_aod_fullscreen">true</bool>' "$xml_file" || fail "cannot add AOD flag"
    fi

    # 修改后确认目标开关确实以 true 的形式存在。
    grep -q '^[[:space:]]*<bool[[:space:]]\+name="support_aod_fullscreen">true</bool>[[:space:]]*$' "$xml_file" || fail "AOD flag verification failed"
done

# 没有可处理的 XML 时停止，不发布空目录。
[ "$xml_count" -gt 0 ] || fail "no XML files found"
# 创建最终副本的父目录。
mkdir -p "${TARGET_DIR%/*}" || fail "cannot create target parent"
# 一次性发布全部处理完成的目录。
mv "$STAGE_DIR" "$TARGET_DIR" || fail "cannot publish device_features"
# 记录准备完成。
log "prepared $xml_count XML file(s)"

# 非 KernelSU 环境到此结束，交给 Magisk 的自动挂载处理模块 system 目录。
[ "$KSU" = "true" ] || exit 0

# KernelSU 环境把完整模块副本一次性 bind 到系统原目录。
mount -o bind "$TARGET_DIR" "$FEATURE_DIR" || fail "bind mount failed"
# 记录 KernelSU 的手动挂载成功。
log "mount method: bind"
# 正常结束启动脚本。
exit 0
