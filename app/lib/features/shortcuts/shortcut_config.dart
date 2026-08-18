/// 快捷指令相关配置。
///
/// 用户路径：App 内点「添加快捷指令」→ 打开 iCloud 预置指令 → 一键安装。
/// 预置指令须已拼好（用户不用自己搜操作）：
/// 1. 获取剪贴板
/// 2. 保存剪贴板链接（链接 = 上一步剪贴板；App Intent，不打开 App）
/// 3. 拷贝到剪贴板（文本留空，用于清空）
///
/// 发布：快捷指令 → 分享 →「拷贝 iCloud 链接」→ 填入 [installIcloudUrl]。
/// 切勿再填会打开 `supercollection://` 的旧链接。
class ShortcutConfig {
  ShortcutConfig._();

  /// 预置完整后台保存指令的 iCloud 链接。
  /// 用 `--dart-define=SHORTCUT_INSTALL_URL=...` 或改 defaultValue。
  static const installIcloudUrl = String.fromEnvironment(
    'SHORTCUT_INSTALL_URL',
    defaultValue:
        'https://www.icloud.com/shortcuts/84284ece487f4e74a805fb82d4df9211',
  );

  /// 旧版：会打开 App（仅兼容，不用于一键安装）
  static const saveClipboardUri = 'supercollection://save';

  static String saveUrlUri(String url) =>
      'supercollection://save?url=${Uri.encodeComponent(url)}';
}
