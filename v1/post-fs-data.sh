#!/system/bin/sh
# 生成并校验 device_features 副本，最后一次性挂载生效。

# FEATURE_DIR 是系统原始目录；TARGET_DIR 是模块副本，STAGE_DIR 用于完成前暂存。
MODDIR="${0%/*}"
FEATURE_DIR="/product/etc/device_features"
TARGET_DIR="$MODDIR/system/product/etc/device_features"
STAGE_DIR="$MODDIR/.device_features.new"
OVERLAY_ERROR="$MODDIR/.overlay-error"
BIND_ERROR="$MODDIR/.bind-error"
MOUNT_MARKER="$TARGET_DIR/.HyperOS3EnableAOD-manual-mount"

# 官方约定：仅用 KSU=true 判断 KernelSU，不通过路径、进程或兼容变量猜测。
IS_KSU=0
[ "$KSU" = "true" ] && IS_KSU=1

log() {
    echo "[HyperOS3EnableAOD] $*"
}

fail() {
    # 失败只清理未完成的模块副本，不修改系统原始目录。
    log "ERROR: $*"
    rm -rf "$STAGE_DIR"
    exit 1
}

validate_xml() {
    xml_file="$1"

    # 有 xmllint 时检查完整语法；无论是否存在，都严格检查根节点和目标配置。
    if command -v xmllint >/dev/null 2>&1; then
        xmllint --noout "$xml_file" >/dev/null 2>&1 || return 1
    fi

    [ "$(grep -Ec '^[[:space:]]*<features([[:space:]][^>]*)?>[[:space:]]*$' "$xml_file")" -eq 1 ] || return 1
    [ "$(grep -Ec '^[[:space:]]*</features>[[:space:]]*$' "$xml_file")" -eq 1 ] || return 1
    [ "$(grep -c 'support_aod_fullscreen' "$xml_file")" -eq 1 ] || return 1
    [ "$(grep -Ec '^[[:space:]]*<bool[[:space:]]+name="support_aod_fullscreen">true</bool>[[:space:]]*$' "$xml_file")" -eq 1 ] || return 1
}

update_xml() {
    xml_file="$1"
    # 闭合标签必须唯一，避免把配置插入错误位置或多次插入。
    close_count=$(grep -Ec '^[[:space:]]*</features>[[:space:]]*$' "$xml_file")
    [ "$close_count" -eq 1 ] || return 1

    key_count=$(grep -c 'support_aod_fullscreen' "$xml_file")
    case "$key_count" in
        0)
            # 不存在时，在唯一的 </features> 前加入配置。
            sed -i '/^[[:space:]]*<\/features>[[:space:]]*$/i\    <bool name="support_aod_fullscreen">true</bool>' "$xml_file" || return 1
            ;;
        1)
            # 已存在时只接受标准 true/false 节点，并统一维护为 true。
            node_count=$(grep -Ec '^[[:space:]]*<bool[[:space:]]+name="support_aod_fullscreen">(true|false)</bool>[[:space:]]*$' "$xml_file")
            [ "$node_count" -eq 1 ] || return 1
            sed -i 's|^[[:space:]]*<bool[[:space:]]\+name="support_aod_fullscreen">\(true\|false\)</bool>[[:space:]]*$|    <bool name="support_aod_fullscreen">true</bool>|' "$xml_file" || return 1
            ;;
        *)
            # 重复配置含义不明确，拒绝继续，避免生成可能无法解析的 XML。
            return 1
            ;;
    esac

    validate_xml "$xml_file"
}

is_mountpoint() {
    awk -v path="$FEATURE_DIR" '$5 == path { found=1 } END { exit !found }' /proc/self/mountinfo
}

validate_mounted_tree() {
    [ -f "$MOUNT_MARKER" ] || return 1
    [ -f "$FEATURE_DIR/.HyperOS3EnableAOD-manual-mount" ] || return 1
    cmp -s "$MOUNT_MARKER" "$FEATURE_DIR/.HyperOS3EnableAOD-manual-mount" || return 1

    mounted_count=0
    for expected in "$TARGET_DIR"/*.xml; do
        [ -f "$expected" ] || continue
        filename=${expected##*/}
        visible="$FEATURE_DIR/$filename"
        [ -f "$visible" ] || return 1
        cmp -s "$expected" "$visible" || return 1
        validate_xml "$visible" || return 1
        mounted_count=$((mounted_count + 1))
    done
    [ "$mounted_count" -gt 0 ] || return 1
    is_mountpoint
}

cleanup_own_mount() {
    if is_mountpoint; then
        # 专属标记不匹配时绝不卸载，避免破坏 Hybrid Mount 或其他模块。
        [ -f "$FEATURE_DIR/.HyperOS3EnableAOD-manual-mount" ] || return 1
        cmp -s "$MOUNT_MARKER" "$FEATURE_DIR/.HyperOS3EnableAOD-manual-mount" || return 1
        umount "$FEATURE_DIR" 2>/dev/null || return 1
    fi
    ! is_mountpoint
}

mount_features() {
    [ -d "$TARGET_DIR" ] || fail "validated module copy is missing"
    [ -r /proc/self/mountinfo ] || fail "cannot inspect current mount state"

    # 不在未知挂载之上继续叠加；若可见内容已经正是本副本，则直接成功。
    if is_mountpoint; then
        if validate_mounted_tree; then
            log "device_features already provided by framework; no extra mount added"
            return 0
        fi
        fail "device_features is already mounted by another layer"
    fi

    rm -f "$OVERLAY_ERROR" "$BIND_ERROR"

    # 只读双 lowerdir OverlayFS：模块副本优先，系统原目录作为下层兜底。
    if grep -qw overlay /proc/filesystems; then
        if mount -t overlay -o "ro,lowerdir=$TARGET_DIR:$FEATURE_DIR" HyperOS3EnableAOD "$FEATURE_DIR" 2>"$OVERLAY_ERROR"; then
            if validate_mounted_tree; then
                rm -f "$OVERLAY_ERROR"
                log "mount method: overlayfs"
                return 0
            fi
            log "OverlayFS mounted but verification failed"
            cleanup_own_mount || fail "cannot clean failed OverlayFS mount"
        else
            overlay_reason=$(tr '\n' ' ' < "$OVERLAY_ERROR" 2>/dev/null)
            log "OverlayFS mount failed: ${overlay_reason:-unknown error}"
            if is_mountpoint; then
                cleanup_own_mount || fail "cannot clean incomplete OverlayFS mount"
            fi
        fi
    else
        log "OverlayFS unavailable in /proc/filesystems"
    fi

    # OverlayFS 不可用、失败或已清理验证失败时，才尝试一次完整目录 bind。
    if mount -o bind "$TARGET_DIR" "$FEATURE_DIR" 2>"$BIND_ERROR"; then
        if validate_mounted_tree; then
            rm -f "$BIND_ERROR"
            log "mount method: bind"
            return 0
        fi
        log "bind mount completed but verification failed"
        cleanup_own_mount || fail "cannot clean failed bind mount"
        fail "bind mount verification failed"
    fi

    bind_reason=$(tr '\n' ' ' < "$BIND_ERROR" 2>/dev/null)
    if is_mountpoint; then
        cleanup_own_mount || fail "cannot clean incomplete bind mount"
    fi
    fail "bind mount failed: ${bind_reason:-unknown error}"
}

[ -d "$FEATURE_DIR" ] || fail "missing source directory: $FEATURE_DIR"

# KSU 手动挂载时动态跳过 Hybrid Mount 对本模块 system 树的自动处理。
# Magisk 删除该标记，prepare 后交给官方 Magic Mount，绝不手动挂载。
if [ "$IS_KSU" -eq 1 ]; then
    : > "$MODDIR/skip_mount" || fail "cannot create KernelSU skip_mount marker"
else
    rm -f "$MODDIR/skip_mount" || fail "cannot remove stale skip_mount marker"
fi

# 只读复制系统原目录的全部内容；后续修改仅发生在暂存副本中。
# 先清除上次副本，确保本轮失败时框架不会挂载陈旧内容。
rm -rf "$TARGET_DIR"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR" || fail "cannot create staging directory"
cp -af "$FEATURE_DIR/." "$STAGE_DIR/" || fail "cannot copy complete source directory"

source_count=0
processed_count=0
for src in "$FEATURE_DIR"/*.xml; do
    [ -f "$src" ] || continue
    source_count=$((source_count + 1))
    filename=${src##*/}
    dest="$STAGE_DIR/$filename"

    [ -f "$dest" ] || fail "copied XML is missing: $filename"
    update_xml "$dest" || fail "XML validation or update failed: $filename"
    processed_count=$((processed_count + 1))
done

[ "$source_count" -gt 0 ] || fail "no XML files found"
[ "$processed_count" -eq "$source_count" ] || fail "processed file count mismatch"

# KSU 手动挂载专属标记；用于挂载后验证和失败清理归属。
if [ "$IS_KSU" -eq 1 ]; then
    printf '%s\n' 'HyperOS3EnableAOD:manual' > "$STAGE_DIR/.HyperOS3EnableAOD-manual-mount" || fail "cannot create mount ownership marker"
fi

# 仅当全部 XML 都成功后才发布副本，绝不让挂载阶段看到半成品。
mkdir -p "${TARGET_DIR%/*}" || fail "cannot create module target parent"
mv "$STAGE_DIR" "$TARGET_DIR" || fail "cannot publish validated directory"
log "prepared $processed_count validated XML file(s)"

# Magisk 到此结束，随后由官方 Magic Mount 自动处理模块 system 树。
[ "$IS_KSU" -eq 1 ] || exit 0

# 标准 KSU 对照版在同一 post-fs-data 中受控手动挂载。
mount_features || fail "no mount method succeeded"
exit 0
