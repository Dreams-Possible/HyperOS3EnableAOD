on_install() {
  ui_print "- 正在释放文件"
  unzip -o "$ZIPFILE" 'system/*' -d $MODPATH >&2
}
set_permissions() {
  set_perm_recursive  $MODPATH  0  0  0755  0644  
}
CommonPath=$MODPATH/common
  ui_print "*******************************"
  ui_print "  注意！"
  ui_print "  模块仅在小米13pro"
  ui_print "  HyperOS2.0.0.21 Beta版本测试"
  ui_print "  启用状态栏渐进模糊效果    "
  ui_print "  强制开始AI景深视频壁纸  "
  ui_print "  合并可变刷新率  "
  ui_print "  最低亮度1hz刷新率"
  ui_print "  启用全屏Aod息屏显示   "
  ui_print "  强制解锁音乐触感，UI开关不生效，硬件不支持？   "
  ui_print "  启用8gen2核心分配   "
  ui_print "  开启dm设备映射器   "
  ui_print "  恢复HDR支持  "
  ui_print "*******************************"
if [ ! -d ${CommonPath} ];then
  ui_print "模块高级设置不需要修复!"
elif [ "`ls -A ${CommonPath}`" = "" ];then
    ui_print "模块高级设置为空!"
    rm  -rf  ${CommonPath}
else
  ui_print "- 正在进行模块高级设置"
  mv  ${CommonPath}/*  $MODPATH
  rm  -rf ${CommonPath}
fi
OUTFD=$2
ZIPFILE=$3
mount /data 2>/dev/null
  SKIPUNZIP=1
echo "*******************************"
echo "请于20秒内按下任意音量键以确定安装"
echo "*******************************"
overtime=0
while [ ${overtime} -lt 20 ]; do
    keystate=$(timeout 1 getevent -qlc 1 | grep -i "KEY_VOLUME" | grep -iw "DOWN")
    let overtime++
    if [ ! -z "$keystate" ]; then
        break
    fi
done

