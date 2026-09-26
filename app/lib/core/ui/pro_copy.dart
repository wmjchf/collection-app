/// Pro（太子/帝王）面向用户的奏折风文案
String unreadSectionTitle({required bool isPro}) => isPro ? '待阅' : '未读';

String unreadEmptyText({required bool isPro}) =>
    isPro ? '暂无待阅' : '暂无未读';

String markAsUnreadLabel({required bool isPro}) =>
    isPro ? '标为待阅' : '标为未读';

String markedAsUnreadToast({required bool isPro}) =>
    isPro ? '已标为待阅' : '已标为未读';

String recentReadSectionTitle({required bool isPro}) =>
    isPro ? '朕已阅' : '最近阅读';

String recentReadEmptyText({required bool isPro}) =>
    isPro ? '暂无朕已阅' : '暂无最近阅读';

/// 收藏页筛选 / 列表标题：批注 → 朕的朱批
String annotationSectionTitle({required bool isPro}) =>
    isPro ? '朕的朱批' : '批注';

/// 工具条等短文案
String addAnnotationLabel({required bool isPro}) =>
    isPro ? '加朱批' : '加批注';

String annotationSavedToast({required bool isPro}) =>
    isPro ? '朱批已保存' : '批注已保存';

String annotationListHint({required bool isPro}) => isPro
    ? '点一条可查看或编辑朱批'
    : '点一条可查看或编辑批注';

String annotationEmptyNoteHint({required bool isPro}) =>
    isPro ? '暂无朱批 · 点击可添加' : '暂无批注 · 点击可添加';

String annotationEditBodyWarning({required bool isPro}) => isPro
    ? '本篇已有高亮朱批，修改正文后朱批位置可能不准确。'
    : '本篇已有高亮批注，修改正文后批注位置可能不准确。';

String annotationSheetTitle({required bool isPro, required bool isCreate}) {
  if (isCreate) return isPro ? '添加朱批' : '添加批注';
  return isPro ? '编辑朱批' : '编辑批注';
}

String annotationNoteHint({required bool isPro}) =>
    isPro ? '可选：写一句朱批' : '可选：写一句批注';

String deleteAnnotationTitle({required bool isPro}) =>
    isPro ? '删除朱批？' : '删除批注？';

String deleteAnnotationLabel({required bool isPro}) =>
    isPro ? '删除朱批' : '删除批注';

/// 系统筛选展示名（按 code 覆写）
String systemFilterDisplayName(String code, String fallback, {required bool isPro}) {
  if (code == 'annotated') return annotationSectionTitle(isPro: isPro);
  return fallback;
}
