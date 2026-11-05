#!/bin/sh
# WechatOpenSDK（fluwx SPM）不附带厂商 dSYM；Xcode 16+ 上传 App Store 会因缺 UUID 失败。
# 从嵌入的二进制生成占位 dSYM（UUID 对齐即可过校验）。
set -e

FRAMEWORK_BIN="${TARGET_BUILD_DIR}/${WRAPPER_NAME}/Frameworks/WechatOpenSDK.framework/WechatOpenSDK"
if [ ! -f "$FRAMEWORK_BIN" ]; then
  FRAMEWORK_BIN="${BUILT_PRODUCTS_DIR}/WechatOpenSDK.framework/WechatOpenSDK"
fi

if [ ! -f "$FRAMEWORK_BIN" ]; then
  echo "note: WechatOpenSDK binary not found; skip dSYM"
  exit 0
fi

if [ -z "${DWARF_DSYM_FOLDER_PATH:-}" ]; then
  echo "note: DWARF_DSYM_FOLDER_PATH empty; skip dSYM"
  exit 0
fi

DSYM_OUT="${DWARF_DSYM_FOLDER_PATH}/WechatOpenSDK.framework.dSYM"
rm -rf "$DSYM_OUT"
/usr/bin/xcrun dsymutil -o "$DSYM_OUT" "$FRAMEWORK_BIN"
echo "Generated WechatOpenSDK dSYM → $DSYM_OUT"
