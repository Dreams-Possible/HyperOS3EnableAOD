#!/system/bin/sh
# v2 自动挂载验证版：只生成安全副本，挂载完全交给 Magisk/KernelSU 框架。

MODDIR="${0%/*}"
FEATURE_DIR="/product/etc/device_features"
TARGET_DIR="$MODDIR/system/product/etc/device_features"
STAGE_DIR="$MODDIR/.device_features.new"

log() {
    echo "[HyperOS3EnableAOD] $*"
}

fail() {
    # 失败只清理模块暂存副本，系统原目录始终不写入。
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

    # 闭合标签必须唯一，避免插入错误位置或重复配置。
    close_count=$(grep -Ec '^[[:space:]]*</features>[[:space:]]*$' "$xml_file")
    [ "$close_count" -eq 1 ] || return 1

    key_count=$(grep -c 'support_aod_fullscreen' "$xml_file")
    case "$key_count" in
        0)
            sed -i '/^[[:space:]]*<\/features>[[:space:]]*$/i\    <bool name="support_aod_fullscreen">true</bool>' "$xml_file" || return 1
            ;;
        1)
            node_count=$(grep -Ec '^[[:space:]]*<bool[[:space:]]+name="support_aod_fullscreen">(true|false)</bool>[[:space:]]*$' "$xml_file")
            [ "$node_count" -eq 1 ] || return 1
            sed -i 's|^[[:space:]]*<bool[[:space:]]\+name="support_aod_fullscreen">\(true\|false\)</bool>[[:space:]]*$|    <bool name="support_aod_fullscreen">true</bool>|' "$xml_file" || return 1
            ;;
        *)
            return 1
            ;;
    esac

    validate_xml "$xml_file"
}

[ -d "$FEATURE_DIR" ] || fail "missing source directory: $FEATURE_DIR"

# 完整只读复制后逐 XML 修改；先移除旧副本，防止失败时框架挂载陈旧内容。
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

# 全部成功后才发布到标准模块路径；两种框架随后各自自动挂载。
mkdir -p "${TARGET_DIR%/*}" || fail "cannot create module target parent"
mv "$STAGE_DIR" "$TARGET_DIR" || fail "cannot publish validated directory"
log "prepared $processed_count validated XML file(s); framework mount requested"
exit 0

