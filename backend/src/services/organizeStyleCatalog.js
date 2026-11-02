/** 分类习惯：与 App survey 小测对齐 */
const ORGANIZE_STYLES = ['coarse', 'topic', 'fine'];

/** 界面文案用图书情报既有术语：粗分 / 主题分类 / 细分 */
const ORGANIZE_STYLE_META = {
  coarse: {
    id: 'coarse',
    label: '粗分',
    summary: '类目少、外延宽，相近主题归入同一大类',
  },
  topic: {
    id: 'topic',
    label: '主题分类',
    summary: '按主题设类，专指适中（常用）',
  },
  fine: {
    id: 'fine',
    label: '细分',
    summary: '类目较专指、外延窄，但仍避免一文一类',
  },
};

function normalizeOrganizeStyle(raw) {
  const id = String(raw || '').trim();
  return ORGANIZE_STYLES.includes(id) ? id : null;
}

/** 注入归类 prompt 的偏好说明 */
function organizeStylePromptHint(style) {
  const id = normalizeOrganizeStyle(style) || 'topic';
  if (id === 'coarse') {
    return (
      '【用户分类习惯：粗分】类目宜少、外延宜宽，相近主题并入同一大类；' +
      '仍禁止「科技/生活」等过宽名，禁止一文一类。'
    );
  }
  if (id === 'fine') {
    return (
      '【用户分类习惯：细分】类目宜更专指、外延宜窄，可拆清点子主题；' +
      '仍禁止单篇热词/型号作类名，禁止一文一类。'
    );
  }
  return (
    '【用户分类习惯：主题分类】按主题设类、专指适中；' +
    '专名进所属主题类；禁止一文一类。'
  );
}

module.exports = {
  ORGANIZE_STYLES,
  ORGANIZE_STYLE_META,
  normalizeOrganizeStyle,
  organizeStylePromptHint,
};
