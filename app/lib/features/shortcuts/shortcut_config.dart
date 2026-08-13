/// 快捷指令相关配置。
///
/// [installIcloudUrl]：预置「从剪贴板保存」的 iCloud 快捷指令链接。
/// 有值时，设置页「添加快捷指令」一键打开该链接；为空则走手动引导（复制 URL Scheme）。
class ShortcutConfig {
  ShortcutConfig._();

  /// 发布预置指令后填入，例如 https://www.icloud.com/shortcuts/xxxx
  static const installIcloudUrl = String.fromEnvironment(
    'SHORTCUT_INSTALL_URL',
    defaultValue: '',
  );

  /// 从剪贴板保存（无参数）
  static const saveClipboardUri = 'supercollection://save';

  /// 保存指定 URL：`supercollection://save?url=<encoded>`
  static String saveUrlUri(String url) =>
      'supercollection://save?url=${Uri.encodeComponent(url)}';
}
