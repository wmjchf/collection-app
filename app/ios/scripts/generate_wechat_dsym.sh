#!/bin/sh
# WechatOpenSDK（fluwx SPM）两处 App Store 坑：
# 1) 厂商不附 dSYM → 缺 UUID 上传失败
# 2) Info.plist MinimumOSVersion(12) 与嵌入后二进制 minos(跟主工程，如 15) 不一致 → ITMS-90208
set -e

FRAMEWORK_DIR="${TARGET_BUILD_DIR}/${WRAPPER_NAME}/Frameworks/WechatOpenSDK.framework"
if [ ! -d "$FRAMEWORK_DIR" ]; then
  FRAMEWORK_DIR="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/WechatOpenSDK.framework"
fi
if [ ! -d "$FRAMEWORK_DIR" ]; then
  FRAMEWORK_DIR="${BUILT_PRODUCTS_DIR}/WechatOpenSDK.framework"
fi

FRAMEWORK_BIN="${FRAMEWORK_DIR}/WechatOpenSDK"
PLIST="${FRAMEWORK_DIR}/Info.plist"

if [ ! -f "$FRAMEWORK_BIN" ] || [ ! -f "$PLIST" ]; then
  echo "note: WechatOpenSDK.framework not found; skip"
  exit 0
fi

# --- ITMS-90208: plist MinimumOSVersion 对齐主工程 / 二进制 minos ---
TARGET_MIN="${IPHONEOS_DEPLOYMENT_TARGET:-15.0}"
CURRENT_MIN="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$PLIST" 2>/dev/null || true)"
if [ "$CURRENT_MIN" != "$TARGET_MIN" ]; then
  /usr/libexec/PlistBuddy -c "Set :MinimumOSVersion $TARGET_MIN" "$PLIST" \
    || /usr/libexec/PlistBuddy -c "Add :MinimumOSVersion string $TARGET_MIN" "$PLIST"
  echo "Set WechatOpenSDK MinimumOSVersion $CURRENT_MIN → $TARGET_MIN"

  # 改 plist 后需重签 framework，否则嵌套签名校验可能失败
  if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]; then
    /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
      --preserve-metadata=identifier,entitlements,flags --timestamp=none \
      "$FRAMEWORK_DIR"
    echo "Re-signed WechatOpenSDK.framework"
  fi
else
  echo "note: WechatOpenSDK MinimumOSVersion already $TARGET_MIN"
fi

# --- 生成占位 dSYM（UUID 对齐即可过校验）---
if [ -z "${DWARF_DSYM_FOLDER_PATH:-}" ]; then
  echo "note: DWARF_DSYM_FOLDER_PATH empty; skip dSYM"
  exit 0
fi

DSYM_OUT="${DWARF_DSYM_FOLDER_PATH}/WechatOpenSDK.framework.dSYM"
rm -rf "$DSYM_OUT"
/usr/bin/xcrun dsymutil -o "$DSYM_OUT" "$FRAMEWORK_BIN"
echo "Generated WechatOpenSDK dSYM → $DSYM_OUT"
