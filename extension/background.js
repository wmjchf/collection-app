import { canSaveUrl, getSession, saveUrl } from './api.js';

chrome.sidePanel.setPanelBehavior({ openPanelOnActionClick: true }).catch(() => {});

chrome.runtime.onInstalled.addListener(() => {
  chrome.sidePanel.setPanelBehavior({ openPanelOnActionClick: true }).catch(() => {});
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: 'conflux-save',
      title: '收藏到 奏折',
      contexts: ['page', 'link', 'selection'],
    });
  });
});

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId !== 'conflux-save') return;
  const url = info.linkUrl || tab?.url;
  await collect(url, tab?.title);
});

chrome.commands.onCommand.addListener(async (command) => {
  if (command !== 'save-page') return;
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  await collect(tab?.url, tab?.title);
});

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type !== 'SAVE_URL') return;
  collect(message.url, message.title)
    .then((result) => sendResponse({ ok: true, ...result }))
    .catch((err) => sendResponse({ ok: false, message: err.message }));
  return true;
});

async function collect(url, title) {
  const session = await getSession();
  if (!session) {
    notify('请先登录', '点工具栏图标，在右侧用手机号登录后再收藏。');
    throw new Error('请先登录');
  }
  if (!canSaveUrl(url)) {
    notify('无法收藏', '当前页不是网页链接。');
    throw new Error('当前页不是网页链接');
  }

  const result = await saveUrl(url);
  const existed = Boolean(result.existed);
  const headline = existed ? '已收藏过' : '已收藏';
  const body = title?.trim() || url;
  notify(headline, body);
  flashBadge(existed ? '·' : '✓');
  return {
    existed,
    message: result.message || headline,
    item: result.item || null,
  };
}

function notify(title, message) {
  chrome.notifications.create({
    type: 'basic',
    iconUrl: 'icons/icon128.png',
    title,
    message: String(message || '').slice(0, 180),
  });
}

async function flashBadge(text) {
  await chrome.action.setBadgeBackgroundColor({ color: '#2A4F32' });
  await chrome.action.setBadgeText({ text });
  setTimeout(() => chrome.action.setBadgeText({ text: '' }), 1600);
}
