const helpImageOss = require('./helpImageOss');

/** App 本地帮助页配图：固定 OSS 对象键（help/ 前缀） */
const SETS = {
  ai_auto_tags: [
    'help/ai-auto-tags-fig1.png',
    'help/ai-auto-tags-fig2.png',
    'help/ai-auto-tags-fig3.png',
  ],
  shortcuts: [
    'help/shortcuts-fig1.png',
    'help/shortcuts-fig2.png',
    'help/shortcuts-fig3.png',
    'help/shortcuts-fig4.png',
    'help/shortcuts-fig5.png',
    'help/shortcuts-fig6.png',
  ],
  how_to_add_link: [
    'help/how-to-add-link-share-sheet.png',
    'help/how-to-add-link-paste-dialog.png',
    'help/how-to-add-link-shortcuts.png',
  ],
};

function assertSet(setKey) {
  if (!SETS[setKey]) {
    const err = new Error('帮助配图集不存在');
    err.status = 404;
    throw err;
  }
}

function listSetKeys(setKey) {
  assertSet(setKey);
  return SETS[setKey];
}

function signSet(setKey) {
  assertSet(setKey);
  if (!helpImageOss.isConfigured()) {
    const err = new Error('未配置 OSS（ALIYUN_OSS_REGION、ALIYUN_OSS_BUCKET）');
    err.status = 503;
    err.code = 'OSS_NOT_CONFIGURED';
    throw err;
  }
  const keys = SETS[setKey];
  const urls = helpImageOss.signKeys(keys);
  return {
    set: setKey,
    images: keys.map((key, i) => ({ key, url: urls[i] })),
  };
}

module.exports = {
  SETS,
  listSetKeys,
  signSet,
};
