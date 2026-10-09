#!/system/bin/sh

MODDIR="${0%/*}"
FEATURE_DIR="/product/etc/device_features"
TARGET_DIR="$MODDIR/system/product/etc/device_features"
STAGE_DIR="$MODDIR/.device_features.new"
LOG_FILE="$MODDIR/boot.log"

: > "$LOG_FILE" 2>/dev/null

log() {
    echo "[HyperOS3EnableAOD] $*" >> "$LOG_FILE"
}

fail() {
    log "ERROR: $*"
    rm -rf "$STAGE_DIR"
    exit 1
}

[ -d "$FEATURE_DIR" ] || fail "missing source directory: $FEATURE_DIR"

rm -rf "$TARGET_DIR"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR" || fail "cannot create staging directory"
cp -af "$FEATURE_DIR/." "$STAGE_DIR/" || fail "cannot copy device_features"

xml_count=0
for xml_file in "$STAGE_DIR"/*.xml; do
    [ -f "$xml_file" ] || continue
    xml_count=$((xml_count + 1))

    if grep -Eq '^[[:space:]]*<bool[[:space:]]+name="support_aod_fullscreen">(true|false)</bool>[[:space:]]*$' "$xml_file"; then
        sed -E -i 's#^[[:space:]]*<bool[[:space:]]+name="support_aod_fullscreen">(true|false)</bool>[[:space:]]*$#    <bool name="support_aod_fullscreen">true</bool>#' "$xml_file" || fail "cannot update AOD flag"
    else
        sed -i '/^[[:space:]]*<\/features>[[:space:]]*$/i\    <bool name="support_aod_fullscreen">true</bool>' "$xml_file" || fail "cannot add AOD flag"
    fi

    grep -Eq '^[[:space:]]*<bool[[:space:]]+name="support_aod_fullscreen">true</bool>[[:space:]]*$' "$xml_file" || fail "AOD flag verification failed"
done

[ "$xml_count" -gt 0 ] || fail "no XML files found"
mkdir -p "${TARGET_DIR%/*}" || fail "cannot create target parent"
mv "$STAGE_DIR" "$TARGET_DIR" || fail "cannot publish device_features"
log "prepared $xml_count XML file(s)"

[ "$KSU" = "true" ] || exit 0

OVERLAY_DIR="$(mktemp -d /dev/HyperOS3EnableAOD.XXXXXX 2>> "$LOG_FILE")"
if [ -n "$OVERLAY_DIR" ]; then
    if /system/bin/cp -a --preserve=c "$TARGET_DIR/." "$OVERLAY_DIR/" 2>> "$LOG_FILE"; then
        log "overlay lowerdirs: $OVERLAY_DIR:$FEATURE_DIR"
        if mount -t overlay -o "ro,lowerdir=$OVERLAY_DIR:$FEATURE_DIR" overlay "$FEATURE_DIR" 2>> "$LOG_FILE"; then
            log "mount method: overlayfs"
            exit 0
        fi
    else
        log "cannot prepare tmpfs lowerdir; falling back to bind"
    fi
    rm -rf "$OVERLAY_DIR"
else
    log "cannot create tmpfs lowerdir; falling back to bind"
fi

mount -o bind "$TARGET_DIR" "$FEATURE_DIR" 2>> "$LOG_FILE" || fail "bind mount failed"
log "mount method: bind"
exit 0
