import {
  canSaveUrl,
  clearSession,
  createTag,
  deleteItem,
  deleteTag,
  createTagModule,
  deleteTagModule,
  renameTagModule,
  fetchHome,
  fetchItem,
  fetchRoam,
  fetchSystemFilters,
  getSession,
  listItems,
  listModuleItems,
  listTagItems,
  listTagModules,
  listTags,
  login,
  listItemTags,
  patchItem,
  reparseItem,
  saveUrl,
  searchItems,
  searchTags,
  sendCode,
  setItemTags,
} from './api.js';

const PAGE = 30;
const $ = (id) => document.getElementById(id);

const loginEl = $('login');
const appEl = $('app');
const homeEl = $('home');
const collectionEl = $('collection');
const moreEl = $('more');
const searchEl = $('search');
const detailEl = $('detail');
const tabbarEl = $('tabbar');
const overlayEl = $('overlay');
const toastEl = $('toast');

const phoneInput = $('phone');
const codeInput = $('code');
const sendBtn = $('send');
const loginBtn = $('login-btn');
const saveBtn = $('save-btn');
const agreedEl = $('agreed');
const homeBody = $('home-body');
const collectionBody = $('collection-body');
const moreTitle = $('more-title');
const moreList = $('more-list');
const moreStatus = $('more-status');
const moreAction = $('more-action');
const moreSpacer = $('more-spacer');
const searchInput = $('search-input');
const searchClear = $('search-clear');
const searchIdle = $('search-idle');
const searchTagsEl = $('search-tags');
const searchContentHead = $('search-content-head');
const searchList = $('search-list');
const searchStatus = $('search-status');
const detailBody = $('detail-body');
const detailMore = $('detail-more');
const detailMenu = $('detail-menu');
const addUrl = $('add-url');
const addError = $('add-error');
const addSave = $('add-save');
const addHint = $('add-hint');
const nameInput = $('name-input');
const nameError = $('name-error');
const nameSave = $('name-save');
const roamPlayerEl = $('roam-player');
const roamPlayerDeck = $('roam-player-deck');

function platformIdFromHost(hostname) {
  let host = String(hostname || '')
    .trim()
    .toLowerCase()
    .replace(/\.$/, '');
  if (!host) return '';
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host) || host.includes(':')) return '';
  if (host === 'localhost') return 'localhost';
  host = host.replace(/^www\./, '');
  host = host.replace(/^(m|mobile|wap|app|www\d*)\./, '');
  const parts = host.split('.').filter(Boolean);
  if (!parts.length) return '';
  const last2 = parts.length >= 2 ? parts.slice(-2).join('.') : '';
  let brand;
  if (
    parts.length >= 3 &&
    ['com.cn', 'net.cn', 'org.cn', 'co.uk', 'com.hk', 'com.tw'].includes(last2)
  ) {
    brand = parts[parts.length - 3];
  } else if (parts.length >= 2) {
    brand = parts[parts.length - 2];
  } else {
    brand = parts[0];
  }
  const id = String(brand || '')
    .replace(/[^a-z0-9-]/gi, '')
    .toLowerCase();
  if (!id || id === 'www') return '';
  return id;
}

function platformLabel(platform, url) {
  const p = String(platform || '').trim();
  if (p && p !== 'web') return p;
  try {
    const host = url ? new URL(String(url)).hostname : '';
    const guessed = platformIdFromHost(host);
    if (guessed) return guessed;
  } catch (_) {}
  return p || 'web';
}

const EMPTY_ICON = `<svg viewBox="0 0 24 24" fill="none" stroke="#C5CAD3" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/></svg>`;

const ICON = {
  unread: { bg: '#5B8FF9', svg: '<circle cx="12" cy="12" r="4.5" fill="none" stroke="currentColor" stroke-width="2.4"/><circle cx="12" cy="12" r="1.6"/>' },
  all: { bg: '#6E788C', svg: '<path d="M5 7h14v1.8H5V7zm0 4.1h14v1.8H5v-1.8zm0 4.1h14V17H5v-1.8z"/>' },
  today: { bg: '#FF9F43', svg: '<rect x="4.5" y="6" width="15" height="13.5" rx="2"/><path d="M8 4.5v3M16 4.5v3M4.5 10h15" fill="none" stroke="#fff" stroke-width="1.6"/>' },
  untagged: { bg: '#8B929C', svg: '<path d="M12.8 4.8 19.2 11a2 2 0 0 1 0 2.8l-5.4 5.4a2 2 0 0 1-2.8 0L4.6 13V4.8z"/><path d="M5 19 19 5" fill="none" stroke="#fff" stroke-width="1.8" stroke-linecap="round"/>' },
  annotated: { bg: '#A270F5', svg: '<path d="M5 18.5 7.2 12 16 3.2l4.8 4.8L12 16.8z"/><path d="M14.2 5l4.8 4.8" fill="none" stroke="#fff" stroke-width="1.2"/>' },
  recent_read: { bg: '#40BAC4', svg: '<circle cx="12" cy="12" r="7.5" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 8v4.5l3 1.8" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>' },
  archived: { bg: '#96A0AF', svg: '<path d="M4.5 7.5h15v3h-15z"/><path d="M6 10.5h12V19H6z"/>' },
  article: { bg: '#5B8FF9', svg: '<path d="M6 4.5h9.5L18 7v12.5H6z" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M8.5 10h7M8.5 13.5h7M8.5 17h4.5" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>' },
  gallery: { bg: '#52C41A', svg: '<rect x="3.5" y="6.5" width="12.5" height="10.5" rx="1.5"/><path d="M8 16.5l2.2-2.8 1.6 1.8 2.4-3.2 2.8 4.2H8z"/><rect x="8" y="4.5" width="12.5" height="10.5" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.4"/>' },
  video: { bg: '#FF6B6B', svg: '<circle cx="12" cy="12" r="8" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M10 8.8v6.4l5.2-3.2z"/>' },
  trash: { bg: '#F56C6C', svg: '<path d="M5 8h14l-1.2 12H6.2z"/><path d="M9 4.5h6l1 3.5H8z"/>' },
  folder: { bg: '#5B8FF9', svg: '<path d="M4 7.2A2 2 0 0 1 6 5.2h3.2L11 7.4h7A2 2 0 0 1 20 9.4v7.4a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z"/>' },
  tagSystem: { bg: '#788CAA', svg: '<path d="M12.8 4.8 19.2 11a2 2 0 0 1 0 2.8l-5.4 5.4a2 2 0 0 1-2.8 0L4.6 13V4.8z"/><circle cx="8.2" cy="8.4" r="1.2" fill="#fff"/>' },
  tagUser: { bg: '#FF8C64', svg: '<path d="M12.8 4.8 19.2 11a2 2 0 0 1 0 2.8l-5.4 5.4a2 2 0 0 1-2.8 0L4.6 13V4.8z"/><circle cx="8.2" cy="8.4" r="1.2" fill="#fff"/>' },
};

const VIEWS = {
  login: loginEl,
  home: homeEl,
  collection: collectionEl,
  more: moreEl,
  search: searchEl,
  detail: detailEl,
};

const TAB_VIEWS = new Set(['home', 'collection']);

let countdown = 0;
let timer = null;
let currentTab = null;
let toastTimer = null;
let searchTimer = null;
let currentView = 'login';
let viewStack = [];
let overlayBusy = false;
let dialogResolver = null;
let nameSubmit = null;
let nameAfterClose = null;
let pickSave = null;
let addSaving = false;
let detailPoll = null;

let more = emptyMore();
let searchState = emptySearch();
let collectionState = emptyCollection();
let detailState = { item: null, error: null, loading: false };
let homeRoamItems = [];
let roamPlayer = {
  snippets: [],
  index: 0,
  mutedSession: false,
  suppressClick: false,
};

/** 对齐 App `_SwipeCard`：跟手位移 + 旋转 + 回弹 / 飞出 */
let roamSwipe = {
  active: false,
  settling: false,
  mode: null,
  pointerId: null,
  startX: 0,
  startY: 0,
  ox: 0,
  oy: 0,
  lastX: 0,
  lastT: 0,
  vx: 0,
};

function emptyMore() {
  return {
    source: 'filter',
    key: '',
    kind: 'unread',
    /** 状态列表形态筛选：null=全部，article|gallery|video */
    mediaKind: null,
    items: [],
    total: 0,
    loading: false,
  };
}

const MEDIA_KIND_CHIPS = [
  { code: null, label: '全部' },
  { code: 'article', label: '文章' },
  { code: 'gallery', label: '图集' },
  { code: 'video', label: '视频' },
];

function emptySearch() {
  return {
    q: '',
    items: [],
    tagItems: [],
    tags: [],
    selectedTagIds: new Set(),
    total: 0,
    loading: false,
    searched: false,
  };
}

function emptyCollection() {
  return {
    filters: [],
    mediaFilters: [],
    modules: [],
    ungrouped: [],
    loading: false,
    error: null,
  };
}

/** 与 App 收藏页一致：所有 / 今天 / 最近阅读 / 批注（不含未读、无标签） */
function collectionFilters(filters) {
  const order = ['all', 'today', 'recent_read', 'annotated'];
  const byCode = new Map((filters || []).map((f) => [f.code, f]));
  return order.map((code) => byCode.get(code)).filter(Boolean);
}

function filterDisplayName(filter) {
  if (filter?.code === 'annotated') return '批注';
  return filter?.name || '';
}

function toast(message) {
  toastEl.hidden = false;
  toastEl.textContent = message;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    toastEl.hidden = true;
  }, 2200);
}

function isAuthError(err) {
  return /登录/.test(err?.message || '');
}

async function handleAuthError(err) {
  if (!isAuthError(err)) return false;
  await clearSession();
  showView('login');
  toast(err.message);
  return true;
}

function showView(name) {
  if (name !== 'detail') stopDetailPoll();
  hideDetailMenu();
  currentView = name;
  loginEl.hidden = name !== 'login';
  appEl.hidden = name === 'login';
  for (const [key, el] of Object.entries(VIEWS)) {
    if (key === 'login') continue;
    el.hidden = key !== name;
  }
  const showNav = TAB_VIEWS.has(name);
  tabbarEl.hidden = !showNav;
  appEl.classList.toggle('with-nav', showNav);
  for (const btn of tabbarEl.querySelectorAll('.tab-item')) {
    btn.classList.toggle('is-active', btn.dataset.tab === name);
  }
}

function pushView(name) {
  viewStack.push(currentView);
  showView(name);
}

function popView() {
  const prev = viewStack.pop() || 'home';
  showView(prev);
  if (prev === 'home') loadHome();
  if (prev === 'collection') loadCollection({ quiet: true });
  if (prev === 'more') loadMorePage({ reset: true });
}

function switchTab(name) {
  viewStack = [];
  if (name === 'collection') {
    showView('collection');
    loadCollection({ quiet: collectionState.filters.length > 0 });
    return;
  }
  showHome();
}

function formatDay(iso) {
  if (!iso) return '';
  const local = new Date(iso);
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const day = new Date(local.getFullYear(), local.getMonth(), local.getDate());
  const diff = Math.round((today - day) / 86400000);
  if (diff === 0) return '今天';
  if (diff === 1) return '昨天';
  const mm = String(local.getMonth() + 1).padStart(2, '0');
  const dd = String(local.getDate()).padStart(2, '0');
  return `${mm}/${dd}`;
}

function formatDateTime(iso) {
  if (!iso) return '';
  const local = new Date(iso);
  const y = local.getFullYear();
  const m = String(local.getMonth() + 1).padStart(2, '0');
  const d = String(local.getDate()).padStart(2, '0');
  const hh = String(local.getHours()).padStart(2, '0');
  const mm = String(local.getMinutes()).padStart(2, '0');
  return `${y}-${m}-${d} ${hh}:${mm}`;
}

function formatRelativeTime(iso) {
  if (!iso) return '';
  const local = new Date(iso);
  const now = new Date();
  const diffMin = Math.floor((now - local) / 60000);
  if (diffMin < 1) return '刚刚';
  if (diffMin < 60) return `${diffMin} 分钟前`;
  if (diffMin < 24 * 60 && now.getDate() === local.getDate()) {
    return `${Math.floor(diffMin / 60)} 小时前`;
  }
  return formatDay(iso);
}

function itemTitle(item) {
  const t = (item.title || '').trim();
  return t || item.url || '无标题';
}

function parseStatusLabel(status) {
  if (status === 'pending') return '解析中';
  if (status === 'failed') return '解析失败';
  if (status === 'success') return '已解析';
  return status || '';
}

function homeUnreadSubtitle(item) {
  return [
    platformLabel(item.platform, item.canonicalUrl || item.url),
    parseStatusLabel(item.status),
  ]
    .filter(Boolean)
    .join(' · ');
}

function subtitleFor(kind, item) {
  if (kind === 'annotated') {
    return `${item.annotationCount || 0} 处标注`;
  }
  if (kind === 'recent') {
    return formatRelativeTime(item.lastReadAt || item.updatedAt);
  }
  if (kind === 'home-unread') {
    return homeUnreadSubtitle(item);
  }
  if (kind === 'search') {
    return [
      platformLabel(item.platform, item.canonicalUrl || item.url),
      formatDay(item.createdAt),
    ]
      .filter(Boolean)
      .join(' · ');
  }
  return [platformLabel(item.platform, item.canonicalUrl || item.url), formatDay(item.createdAt)]
    .filter(Boolean)
    .join(' · ');
}

function roamKindLabel(snippet) {
  if (snippet?.kind === 'thought') return '感想';
  if (snippet?.kind === 'note') return '批注';
  return '高亮';
}

function isDouyin(item) {
  const p = (item.platform || '').toLowerCase();
  if (p === 'douyin') return true;
  for (const raw of [item.canonicalUrl, item.url]) {
    if (!raw) continue;
    try {
      const host = new URL(raw).host.toLowerCase();
      if (host.includes('douyin.com') || host.includes('iesdouyin.com')) {
        return true;
      }
    } catch {
      // ignore
    }
  }
  return false;
}

function isDouyinNoteOrSlides(item) {
  for (const raw of [item.canonicalUrl, item.url]) {
    if (!raw) continue;
    try {
      const path = new URL(raw).pathname.toLowerCase();
      if (path.includes('/note/') || path.includes('/slides/')) return true;
    } catch {
      // ignore
    }
  }
  return false;
}

function hasVideo(item) {
  const v = (item.videoUrl || '').trim();
  if (!v) return false;
  if (isDouyinNoteOrSlides(item)) return false;
  if (isDouyin(item) && imageList(item).length) return false;
  return true;
}

function imageList(item) {
  return Array.isArray(item.imageUrls)
    ? item.imageUrls.map((u) => String(u).trim()).filter(Boolean)
    : [];
}

function displayImages(item) {
  const raw = imageList(item);
  const list = raw.length ? raw : [(item.coverImageUrl || '').trim()].filter(Boolean);
  const out = [];
  const seen = new Set();
  for (const u of list) {
    const key = u.split('?')[0];
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(u);
  }
  return out;
}

function isImageGallery(item) {
  const images = imageList(item);
  if (!images.length) return false;
  if (hasVideo(item)) return false;
  const body = item.content || '';
  if (/!v?\[[^\]]*\]\([^)\s]+\)/.test(body)) return false;
  return true;
}

function previewImages(item) {
  if (isImageGallery(item)) return imageList(item);
  const cover = (item.coverImageUrl || '').trim();
  if (cover) return [cover];
  const first = displayImages(item)[0];
  return first ? [first] : [];
}

function ledePreview(content, maxParagraphs = 3) {
  const normalized = String(content || '').replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  const out = [];
  for (const chunk of normalized.split('\n')) {
    const t = chunk.trim();
    if (!t) continue;
    if (/^[ \t]*!\[[^\]]*\]\([^)\s]+\)[ \t]*$/.test(t)) continue;
    if (/^#{1,4}\s+/.test(t)) break;
    out.push(t);
    if (out.length >= maxParagraphs) break;
  }
  return out.join('\n\n').trim();
}

function previewText(item) {
  const content = (item.content || '').trim();
  if (content) {
    const lede = ledePreview(content);
    if (lede) return lede;
  }
  return (item.summary || '').trim();
}

function stripPreviewMd(text) {
  return String(text)
    .replace(/\{\{\d+\|([\s\S]*?)\}\}/g, '$1')
    .replace(/\*\*(.+?)\*\*/g, '$1')
    .replace(/(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/g, '$1');
}

function itemLink(item) {
  const canonical = (item.canonicalUrl || '').trim();
  if (canonical) return canonical;
  return (item.url || '').trim();
}

/** 桌面扩展：点条目直接打开原文 */
function openItemLink(item) {
  const link = itemLink(item);
  if (!link) {
    toast('暂无链接');
    return;
  }
  chrome.tabs.create({ url: link });
}

async function activeTab() {
  const [t] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  return t || null;
}

async function syncCurrentTab() {
  currentTab = await activeTab();
}

function coverEl(url) {
  const img = document.createElement('img');
  img.className = 'cover';
  img.alt = '';
  img.referrerPolicy = 'no-referrer';
  if (url) {
    img.src = url;
    img.addEventListener('error', () => img.removeAttribute('src'));
  }
  return img;
}

/** 与 App ItemListTile 一致：最多 3 个 #标签，超出 +N */
function tagsLine(tags) {
  const list = Array.isArray(tags) ? tags : [];
  const labels = [];
  for (const tag of list) {
    const n = String(tag?.name || '').trim();
    if (!n) continue;
    labels.push(n.startsWith('#') ? n : `#${n}`);
  }
  if (!labels.length) return '';
  const max = 3;
  if (labels.length <= max) return labels.join('  ');
  return `${labels.slice(0, max).join('  ')}  +${labels.length - max}`;
}

function cardEl(item, kind) {
  const card = document.createElement('button');
  card.type = 'button';
  card.className = 'card';
  card.append(coverEl(item.coverImageUrl));
  const body = document.createElement('div');
  body.className = 'card-body';
  const title = document.createElement('p');
  title.className = 'card-title';
  title.textContent = itemTitle(item);
  const tags = document.createElement('p');
  tags.className = 'card-tags';
  const line = tagsLine(item.tags);
  if (line) tags.textContent = line;
  else tags.innerHTML = '&nbsp;';
  const sub = document.createElement('p');
  sub.className = 'card-sub';
  sub.textContent = subtitleFor(kind, item);
  body.append(title, tags, sub);
  card.append(body);
  card.addEventListener('click', () => openItemLink(item));
  return card;
}

function emptyCard(text) {
  const el = document.createElement('div');
  el.className = 'empty-card';
  el.innerHTML = `${EMPTY_ICON}<span></span>`;
  el.querySelector('span').textContent = text;
  return el;
}

function sectionHead({ title, moreLabel, onMore }) {
  const head = document.createElement('div');
  head.className = 'section-head';
  const h2 = document.createElement('h2');
  h2.textContent = title;
  const moreBtn = document.createElement('button');
  moreBtn.type = 'button';
  moreBtn.className = 'more';
  moreBtn.textContent = moreLabel;
  moreBtn.addEventListener('click', onMore);
  head.append(h2, moreBtn);
  return head;
}

function unreadSectionEl(items) {
  const wrap = document.createElement('section');
  wrap.className = 'home-section';
  wrap.append(
    sectionHead({
      title: '未读',
      moreLabel: '查看更多 ›',
      onMore: () =>
        openMore({
          source: 'filter',
          key: 'unread',
          title: '未读',
          kind: 'unread',
        }),
    }),
  );

  const frame = document.createElement('div');
  frame.className = 'unread-frame';
  if (!items.length) {
    frame.append(emptyCard('暂无未读'));
  } else {
    const cards = document.createElement('div');
    cards.className = 'section-cards';
    for (const item of items.slice(0, 3)) {
      cards.append(cardEl(item, 'home-unread'));
    }
    if (items.length < 3) {
      const tip = document.createElement('p');
      tip.className = 'unread-tip';
      tip.textContent = '未读就这些了';
      cards.append(tip);
    }
    frame.append(cards);
  }
  wrap.append(frame);
  return wrap;
}

function roamMetaText(snippet, hasQuote) {
  const parts = [];
  if (!hasQuote) parts.push(roamKindLabel(snippet));
  const time = formatRelativeTime(snippet.createdAt);
  if (time) parts.push(time);
  const title = (snippet.itemTitle || '').trim();
  if (title) parts.push(title);
  return parts.join(' · ');
}

function roamNoteBlock(snippet, { stacked = false, clamp = true } = {}) {
  const note = document.createElement('div');
  note.className = `roam-note${stacked ? ' is-stacked' : ''}`;
  const badge = document.createElement('span');
  badge.className = 'roam-badge';
  badge.textContent = roamKindLabel(snippet);
  const noteText = document.createElement('p');
  if (!clamp) noteText.classList.add('is-full');
  noteText.textContent = snippet.text;
  note.append(badge, noteText);
  return note;
}

function roamQuoteCard(
  snippet,
  { compact = false, scrollBody = false, onMute = null } = {},
) {
  const card = document.createElement('article');
  card.className = `roam-quote${compact ? ' is-peek' : ''}${scrollBody ? ' is-scroll' : ''}`;

  const hasQuote = Boolean(snippet.quote && String(snippet.quote).trim());
  const primary = hasQuote ? snippet.quote : snippet.text || '';

  const mark = document.createElement('span');
  mark.className = 'roam-quote-mark';
  mark.setAttribute('aria-hidden', 'true');
  mark.textContent = '“';

  const body = document.createElement('p');
  body.className = 'roam-quote-text';
  if (scrollBody) body.classList.add('is-full');
  body.textContent = primary;

  if (scrollBody) {
    card.append(mark);
    const scroll = document.createElement('div');
    scroll.className = 'roam-quote-scroll';
    scroll.append(body);
    if (hasQuote && snippet.text) {
      scroll.append(roamNoteBlock(snippet, { stacked: true, clamp: false }));
    }
    card.append(scroll);
  } else {
    card.append(mark, body);
    if (hasQuote && snippet.text) {
      card.append(roamNoteBlock(snippet, { stacked: false, clamp: true }));
    }
  }

  if (!compact) {
    const metaRow = document.createElement('div');
    metaRow.className = 'roam-meta-row';
    const meta = document.createElement('div');
    meta.className = 'roam-meta';
    meta.textContent = roamMetaText(snippet, hasQuote);
    metaRow.append(meta);
    if (typeof onMute === 'function') {
      const muteBtn = document.createElement('button');
      muteBtn.type = 'button';
      muteBtn.className = 'roam-mute-btn';
      muteBtn.textContent = '不再回顾';
      muteBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        onMute();
      });
      metaRow.append(muteBtn);
    }
    card.append(metaRow);
  }

  return card;
}

async function getRoamMutedIds() {
  const data = await chrome.storage.local.get(['roamMutedIds']);
  const list = Array.isArray(data.roamMutedIds) ? data.roamMutedIds : [];
  return new Set(list.map(String));
}

async function muteRoamId(id) {
  const set = await getRoamMutedIds();
  set.add(String(id));
  await chrome.storage.local.set({ roamMutedIds: [...set] });
}

async function filterRoamVisible(items) {
  const muted = await getRoamMutedIds();
  return (items || []).filter((s) => s?.id && !muted.has(String(s.id)));
}

function fitRoamStackLines(stack) {
  const text = stack.querySelector('.roam-layer-0 .roam-quote-text');
  if (!text) return;
  const lineH = parseFloat(getComputedStyle(text).lineHeight) || 24.8;
  const h = text.clientHeight;
  if (h < 8) return;
  const lines = Math.max(1, Math.floor(h / lineH));
  text.style.setProperty('--roam-lines', String(lines));
  text.style.webkitLineClamp = String(lines);
}

function roamStackEl(items) {
  const stack = document.createElement('button');
  stack.type = 'button';
  stack.className = 'roam-stack';
  stack.title = '开始漫游';
  const show = items.slice(0, 3);
  const peekCount = Math.max(0, show.length - 1);
  stack.style.setProperty('--peek', String(peekCount));

  for (let i = show.length - 1; i >= 0; i -= 1) {
    const layer = document.createElement('div');
    layer.className = `roam-layer roam-layer-${i}`;
    layer.append(roamQuoteCard(show[i], { compact: i > 0 }));
    stack.append(layer);
  }

  // 与 App 一致：点叠卡进播放器，不是进全部列表
  stack.addEventListener('click', () => openRoamPlayer(items));
  const fit = () => fitRoamStackLines(stack);
  requestAnimationFrame(() => {
    fit();
    requestAnimationFrame(fit);
  });
  if (typeof ResizeObserver !== 'undefined') {
    new ResizeObserver(fit).observe(stack);
  }
  return stack;
}

function roamSectionEl(items) {
  const wrap = document.createElement('section');
  wrap.className = 'home-section home-roam';
  wrap.append(
    sectionHead({
      title: '漫游',
      moreLabel: '全部 ›',
      onMore: () => openRoamList(),
    }),
  );

  if (!items.length) {
    const empty = emptyCard('读的时候划重点、写批注或感想，就会出现在这里');
    empty.classList.add('roam-empty');
    wrap.append(empty);
  } else {
    wrap.append(roamStackEl(items));
  }
  return wrap;
}

async function renderHome(data) {
  homeBody.replaceChildren();
  if (!data) {
    const msg = document.createElement('p');
    msg.className = 'list-msg';
    msg.textContent = '加载中…';
    homeBody.append(msg);
    return;
  }
  const roamItems = await filterRoamVisible(data.roam?.items || []);
  homeRoamItems = roamItems;
  homeBody.append(
    unreadSectionEl(data.unread?.items || []),
    roamSectionEl(roamItems),
  );
}

function openRoamList() {
  return openMore({
    source: 'roam',
    key: 'roam',
    title: '漫游',
    kind: 'roam',
  });
}

function resetRoamSwipeState() {
  roamSwipe = {
    active: false,
    settling: false,
    mode: null,
    pointerId: null,
    startX: 0,
    startY: 0,
    ox: 0,
    oy: 0,
    lastX: 0,
    lastT: 0,
    vx: 0,
  };
}

function roamFrontEl() {
  return roamPlayerDeck.querySelector('.roam-player-front');
}

function roamNextEl() {
  return roamPlayerDeck.querySelector('.roam-player-next');
}

function applyRoamSwipeTransform(x, y) {
  const front = roamFrontEl();
  if (!front) return;
  const angle = (x / 420) * 0.28;
  front.style.transform = `translate(${x}px, ${y}px) rotate(${angle}rad)`;
  const w = roamPlayerDeck.clientWidth || 320;
  const p = Math.min(1, Math.abs(x) / (w * 0.42));
  const next = roamNextEl();
  if (next) {
    next.style.transform = `scale(${0.94 + 0.06 * p})`;
  }
}

function clearRoamSwipeTransform() {
  const front = roamFrontEl();
  if (front) front.style.transform = '';
  const next = roamNextEl();
  if (next) next.style.transform = '';
}

function animateRoamSwipeTo(toX, toY, ms) {
  return new Promise((resolve) => {
    roamSwipe.settling = true;
    const fromX = roamSwipe.ox;
    const fromY = roamSwipe.oy;
    const t0 = performance.now();
    const tick = (now) => {
      const t = Math.min(1, (now - t0) / ms);
      roamSwipe.ox = fromX + (toX - fromX) * t;
      roamSwipe.oy = fromY + (toY - fromY) * t;
      applyRoamSwipeTransform(roamSwipe.ox, roamSwipe.oy);
      if (t < 1) {
        requestAnimationFrame(tick);
        return;
      }
      roamSwipe.settling = false;
      resolve();
    };
    requestAnimationFrame(tick);
  });
}

async function dismissRoamFront(dir) {
  const w = roamPlayerDeck.clientWidth || 320;
  roamPlayer.suppressClick = true;
  await animateRoamSwipeTo(dir * (w + 80), roamSwipe.oy * 0.4, 220);
  roamSwipe.ox = 0;
  roamSwipe.oy = 0;
  advanceRoamPlayer();
}

function closeRoamPlayer() {
  const needRefresh = roamPlayer.mutedSession;
  roamPlayerEl.hidden = true;
  roamPlayer = {
    snippets: [],
    index: 0,
    mutedSession: false,
    suppressClick: false,
  };
  resetRoamSwipeState();
  roamPlayerDeck.replaceChildren();
  if (needRefresh) loadHome();
}

async function muteCurrentRoam() {
  const snip = roamPlayer.snippets[roamPlayer.index];
  if (!snip || roamSwipe.settling) return;
  roamPlayer.suppressClick = true;
  const w = roamPlayerDeck.clientWidth || 320;
  // 对齐 App：右上飞出后再换卡
  await animateRoamSwipeTo(w + 80, -48, 280);
  await muteRoamId(snip.id);
  roamPlayer.mutedSession = true;
  roamPlayer.snippets = roamPlayer.snippets.filter((s) => s.id !== snip.id);
  homeRoamItems = homeRoamItems.filter((s) => s.id !== snip.id);
  toast('已不再回顾');
  roamSwipe.ox = 0;
  roamSwipe.oy = 0;
  if (!roamPlayer.snippets.length) {
    closeRoamPlayer();
    return;
  }
  if (roamPlayer.index >= roamPlayer.snippets.length) {
    roamPlayer.index = roamPlayer.snippets.length;
  }
  renderRoamPlayer();
}

function roamDoneCard(finished) {
  const done = document.createElement('div');
  done.className = 'roam-done-card';
  done.innerHTML = `
    <div class="roam-done-icon" aria-hidden="true">
      <svg width="30" height="30" viewBox="0 0 24 24" fill="none">
        <path d="M5 12.5 10 17.5 19 7.5" stroke="#E8A25A" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>
    </div>
    <h3>已完成 ${finished} 条摘录</h3>
    <p>左右滑或点空白处可关闭</p>
    <button type="button" class="roam-done-finish" id="roam-finish">完成漫游</button>
    <button type="button" class="roam-done-continue" id="roam-continue">继续漫游</button>
  `;
  done.querySelector('#roam-finish').addEventListener('click', (e) => {
    e.stopPropagation();
    closeRoamPlayer();
  });
  done.querySelector('#roam-continue').addEventListener('click', (e) => {
    e.stopPropagation();
    roamPlayer.index = 0;
    renderRoamPlayer();
  });
  return done;
}

function renderRoamPlayer() {
  const { snippets, index } = roamPlayer;
  const onDone = index >= snippets.length;
  resetRoamSwipeState();
  roamPlayerDeck.replaceChildren();

  if (!snippets.length) {
    closeRoamPlayer();
    return;
  }

  // 背后空壳（层级感，对齐 App）
  const back = document.createElement('div');
  back.className = 'roam-player-back';
  back.setAttribute('aria-hidden', 'true');
  roamPlayerDeck.append(back);

  if (!onDone && index + 1 < snippets.length) {
    const next = roamQuoteCard(snippets[index + 1], { scrollBody: true });
    next.className = `${next.className} roam-player-next`.trim();
    next.setAttribute('aria-hidden', 'true');
    roamPlayerDeck.append(next);
  }

  const front = document.createElement('div');
  front.className = 'roam-player-front';

  if (onDone) {
    front.append(roamDoneCard(snippets.length));
  } else {
    const card = roamQuoteCard(snippets[index], {
      scrollBody: true,
      onMute: () => muteCurrentRoam(),
    });
    card.classList.add('roam-player-card');
    card.addEventListener('click', () => {
      if (roamPlayer.suppressClick) {
        roamPlayer.suppressClick = false;
        return;
      }
      openRoamSnippetLink(snippets[index]);
    });
    front.append(card);
  }
  roamPlayerDeck.append(front);
}

function advanceRoamPlayer() {
  if (roamPlayer.index >= roamPlayer.snippets.length) return;
  if (roamSwipe.settling) return;
  roamPlayer.index += 1;
  renderRoamPlayer();
}

async function openRoamPlayer(items, startIndex = 0) {
  const visible = await filterRoamVisible(items);
  if (!visible.length) {
    toast('暂无漫游内容');
    return;
  }
  const idx = Math.min(Math.max(Number(startIndex) || 0, 0), visible.length - 1);
  roamPlayer = {
    snippets: visible,
    index: idx,
    mutedSession: false,
    suppressClick: false,
  };
  resetRoamSwipeState();
  roamPlayerEl.hidden = false;
  renderRoamPlayer();
}

async function openRoamSnippetLink(snippet) {
  try {
    const res = await fetchItem(snippet.itemId);
    openItemLink(res.item || { id: snippet.itemId });
  } catch (err) {
    if (await handleAuthError(err)) return;
    toast(err.message || '打开失败');
  }
}

async function loadHome() {
  await renderHome(null);
  try {
    const data = await fetchHome();
    await renderHome(data);
  } catch (err) {
    if (await handleAuthError(err)) return;
    homeBody.replaceChildren();
    const msg = document.createElement('p');
    msg.className = 'list-msg';
    msg.textContent = err.message || '加载失败';
    const retry = document.createElement('button');
    retry.type = 'button';
    retry.className = 'more';
    retry.textContent = '重试';
    retry.style.display = 'block';
    retry.style.margin = '0 auto';
    retry.addEventListener('click', loadHome);
    homeBody.append(msg, retry);
  }
}

async function showHome() {
  showView('home');
  await syncCurrentTab();
  await loadHome();
}

function fillList(container, items, kind) {
  container.replaceChildren();
  for (const item of items) {
    container.append(cardEl(item, kind));
  }
}

function setMoreAction(label) {
  if (label) {
    moreAction.hidden = false;
    moreAction.textContent = label;
    moreSpacer.hidden = true;
  } else {
    moreAction.hidden = true;
    moreSpacer.hidden = false;
  }
}

function kindForFilter(code) {
  if (code === 'annotated') return 'annotated';
  if (code === 'recent_read') return 'recent';
  return 'unread';
}

async function openMore({ source, key, title, kind }) {
  more = {
    source,
    key,
    kind: kind || kindForFilter(key),
    mediaKind: null,
    items: [],
    total: 0,
    loading: false,
  };
  moreTitle.textContent = title;
  moreList.replaceChildren();
  moreStatus.hidden = false;
  moreStatus.textContent = '加载中…';
  setMoreAction('');
  renderMoreMediaChips();
  pushView('more');
  await loadMorePage({ reset: true });
}

function showMoreMediaKinds() {
  return (
    more.source === 'filter' &&
    (more.key === 'unread' ||
      more.key === 'all' ||
      more.key === 'today' ||
      more.key === 'recent_read' ||
      more.key === 'untagged' ||
      more.key === 'annotated')
  );
}

function renderMoreMediaChips() {
  let bar = $('more-media-kinds');
  const show = showMoreMediaKinds();
  if (!show) {
    if (bar) bar.hidden = true;
    return;
  }
  if (!bar) {
    bar = document.createElement('div');
    bar.id = 'more-media-kinds';
    bar.className = 'more-media-kinds';
    moreList.parentNode.insertBefore(bar, moreList);
  }
  bar.hidden = false;
  bar.replaceChildren();
  for (const chip of MEDIA_KIND_CHIPS) {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'more-media-chip';
    if (more.mediaKind === chip.code) btn.classList.add('is-on');
    btn.textContent = chip.label;
    btn.addEventListener('click', () => {
      if (more.mediaKind === chip.code) return;
      more.mediaKind = chip.code;
      renderMoreMediaChips();
      loadMorePage({ reset: true });
    });
    bar.append(btn);
  }
}

async function fetchMorePage(offset) {
  const { source, key, mediaKind } = more;
  if (source === 'tag') {
    return listTagItems(key, { limit: PAGE, offset });
  }
  if (source === 'module') {
    return listModuleItems(key, { limit: PAGE, offset });
  }
  if (source === 'roam') {
    return fetchRoam({ limit: PAGE, offset });
  }
  return listItems({
    filter: key,
    mediaKind: mediaKind || null,
    limit: PAGE,
    offset,
  });
}

async function fillRoamList(container, snippets) {
  container.replaceChildren();
  const visible = await filterRoamVisible(snippets);
  for (let i = 0; i < visible.length; i += 1) {
    const snippet = visible[i];
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'roam-list-item';
    btn.append(roamQuoteCard(snippet));
    // 列表点开：与 App 进阅读对应 —— 扩展打开原文；也可从叠卡播放
    btn.addEventListener('click', () => openRoamSnippetLink(snippet));
    container.append(btn);
  }
  if (!visible.length) {
    const empty = document.createElement('p');
    empty.className = 'list-msg';
    empty.textContent = '读的时候划重点、写批注或感想，就会出现在这里';
    container.append(empty);
  }
}

async function loadMorePage({ reset = false } = {}) {
  if (more.loading) return;
  if (!reset && more.items.length >= more.total) return;
  more.loading = true;
  if (reset) moreStatus.textContent = '加载中…';
  try {
    const offset = reset ? 0 : more.items.length;
    const data = await fetchMorePage(offset);
    const next = Array.isArray(data.items) ? data.items : [];
    more.total = Number(data.total ?? next.length);
    more.items = reset ? next : more.items.concat(next);
    if (more.source === 'roam') await fillRoamList(moreList, more.items);
    else fillList(moreList, more.items, more.kind);
    const hasMore = more.items.length < more.total;
    moreStatus.className = 'list-msg';
    moreStatus.hidden = !hasMore;
    moreStatus.textContent = hasMore ? '上滑加载更多' : '';
    if (!more.items.length) {
      moreStatus.hidden = false;
      moreStatus.className = 'list-msg list-empty';
      moreStatus.replaceChildren();
      const icon = document.createElement('span');
      icon.className = 'list-empty-icon';
      icon.setAttribute('aria-hidden', 'true');
      icon.innerHTML =
        '<svg width="42" height="42" viewBox="0 0 24 24" fill="none" stroke="#C5CAD3" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/></svg>';
      const text = document.createElement('span');
      text.textContent = '暂无内容';
      moreStatus.append(icon, text);
    }
  } catch (err) {
    if (await handleAuthError(err)) return;
    moreStatus.hidden = false;
    moreStatus.className = 'list-msg';
    moreStatus.textContent = err.message || '加载失败';
  } finally {
    more.loading = false;
  }
}

function mergeSearchTags(...lists) {
  const byId = new Map();
  for (const list of lists) {
    for (const tag of list || []) {
      if (!tag?.id) continue;
      const prev = byId.get(tag.id);
      if (!prev || (tag.itemCount || 0) > (prev.itemCount || 0)) {
        byId.set(tag.id, tag);
      }
    }
  }
  return [...byId.values()];
}

function searchVisibleItems() {
  const seen = new Set();
  const merged = [];
  for (const item of [...(searchState.tagItems || []), ...(searchState.items || [])]) {
    if (!item?.id || seen.has(item.id)) continue;
    seen.add(item.id);
    merged.push(item);
  }
  const selected = searchState.selectedTagIds;
  if (!selected || selected.size === 0) return merged;
  return merged.filter((item) => {
    const ids = new Set((item.tags || []).map((t) => t.id));
    for (const id of selected) {
      if (!ids.has(id)) return false;
    }
    return true;
  });
}

function renderSearch() {
  const q = searchInput.value.trim();
  searchClear.hidden = !q;
  const s = searchState;

  if (!s.searched || !q) {
    searchIdle.hidden = false;
    searchTagsEl.hidden = true;
    searchContentHead.hidden = true;
    searchList.replaceChildren();
    searchStatus.hidden = true;
    return;
  }

  searchIdle.hidden = true;
  const visible = searchVisibleItems();
  const filtering = s.selectedTagIds.size > 0;
  const tags = s.tags || [];

  if (s.loading && !visible.length && !tags.length) {
    searchTagsEl.hidden = true;
    searchContentHead.hidden = true;
    searchList.replaceChildren();
    searchStatus.hidden = false;
    searchStatus.textContent = '搜索中…';
    return;
  }

  if (tags.length) {
    searchTagsEl.hidden = false;
    searchTagsEl.replaceChildren();
    const label = document.createElement('div');
    label.className = 'search-tags-label';
    label.textContent = '标签';
    searchTagsEl.append(label);
    const wrap = document.createElement('div');
    wrap.className = 'search-tag-wrap';
    const preview = tags.slice(0, 6);
    for (const tag of preview) {
      const btn = document.createElement('button');
      btn.type = 'button';
      const on = s.selectedTagIds.has(tag.id);
      btn.className = `search-tag-chip${on ? ' is-on' : ''}`;
      const name = String(tag.name || '').trim();
      const hash = name.startsWith('#') ? name : `#${name}`;
      btn.innerHTML =
        '<span class="search-tag-name"></span>';
      btn.querySelector('.search-tag-name').textContent = hash;
      if (tag.itemCount > 0) {
        const c = document.createElement('span');
        c.className = 'search-tag-count';
        c.textContent = String(tag.itemCount);
        btn.append(c);
      }
      btn.addEventListener('click', () => {
        if (s.selectedTagIds.has(tag.id)) s.selectedTagIds.delete(tag.id);
        else s.selectedTagIds.add(tag.id);
        renderSearch();
      });
      wrap.append(btn);
    }
    searchTagsEl.append(wrap);
  } else {
    searchTagsEl.hidden = true;
    searchTagsEl.replaceChildren();
  }

  if (!visible.length && !s.loading) {
    searchContentHead.hidden = true;
    searchList.replaceChildren();
    searchStatus.hidden = false;
    searchStatus.textContent = filtering
      ? '没有相关标签的内容'
      : tags.length
        ? '没有相关内容'
        : `没有「${s.q}」相关的标签或内容`;
    return;
  }

  const textIds = new Set((s.items || []).map((i) => i.id));
  const tagExtra = (s.tagItems || []).filter((i) => i?.id && !textIds.has(i.id))
    .length;
  const total = filtering ? visible.length : Number(s.total || 0) + tagExtra;
  searchContentHead.hidden = false;
  searchContentHead.textContent = filtering
    ? `内容 · ${total}（按所选标签）`
    : `内容 · ${total}`;

  fillList(searchList, visible, 'search');
  const hasMore = !filtering && s.items.length < s.total;
  searchStatus.hidden = !hasMore && !(s.loading && visible.length);
  if (s.loading && visible.length) searchStatus.textContent = '加载中…';
  else if (hasMore) searchStatus.textContent = '上滑加载更多';
  else searchStatus.hidden = true;
}

async function runSearch({ reset = false } = {}) {
  const q = searchInput.value.trim();
  if (!q) {
    searchState = emptySearch();
    renderSearch();
    return;
  }
  if (searchState.loading && !reset) return;
  if (!reset && searchState.items.length >= searchState.total) return;

  searchState.loading = true;
  searchState.q = q;
  searchState.searched = true;
  if (reset) {
    searchState.selectedTagIds = new Set();
    searchState.items = [];
    searchState.tagItems = [];
    searchState.tags = [];
    searchState.total = 0;
    renderSearch();
  }

  try {
    const offset = reset ? 0 : searchState.items.length;
    if (reset) {
      const [textRes, tagRes] = await Promise.all([
        searchItems(q, { limit: PAGE, offset: 0 }),
        searchTags(q, { limit: PAGE, offset: 0 }),
      ]);
      if (searchInput.value.trim() !== q) return;
      const textItems = Array.isArray(textRes.items) ? textRes.items : [];
      const tagItems = Array.isArray(tagRes.items) ? tagRes.items : [];
      searchState.items = textItems;
      searchState.tagItems = tagItems;
      searchState.total = Number(textRes.total ?? textItems.length);
      const itemTags = [];
      for (const item of [...tagItems, ...textItems]) {
        for (const t of item.tags || []) itemTags.push(t);
      }
      searchState.tags = mergeSearchTags(
        textRes.tags,
        tagRes.tags,
        itemTags,
      );
    } else {
      const textRes = await searchItems(q, { limit: PAGE, offset });
      if (searchInput.value.trim() !== q) return;
      const next = Array.isArray(textRes.items) ? textRes.items : [];
      searchState.items = searchState.items.concat(next);
      searchState.total = Number(textRes.total ?? searchState.total);
    }
  } catch (err) {
    if (await handleAuthError(err)) return;
    searchStatus.hidden = false;
    searchStatus.textContent = err.message || '搜索失败';
  } finally {
    searchState.loading = false;
    renderSearch();
  }
}

function iconHtml(spec) {
  return `<span class="nav-icon" style="background:${spec.bg}"><svg viewBox="0 0 24 24" fill="currentColor">${spec.svg}</svg></span>`;
}

function iconForFilter(code) {
  return ICON[code] || ICON.all;
}

function navRow({ title, count, icon, onClick, onDelete }) {
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.className = 'nav-row';
  btn.innerHTML = `${iconHtml(icon)}<span class="name"></span><span class="count"></span><span class="arrow">›</span>`;
  btn.querySelector('.name').textContent = title;
  btn.querySelector('.count').textContent = count ?? '';
  btn.addEventListener('click', onClick);
  if (onDelete) {
    btn.title = '右键删除';
    btn.addEventListener('contextmenu', (e) => {
      e.preventDefault();
      onDelete();
    });
  }
  return btn;
}

function entityGroup(rows) {
  const wrap = document.createElement('div');
  wrap.className = 'entity-group';
  if (!rows.length) {
    wrap.innerHTML = '<div class="entity-empty">暂无内容</div>';
    return wrap;
  }
  for (const row of rows) wrap.append(row);
  return wrap;
}

function sectionLabel(title, { expandable, expanded, onToggle, onAdd } = {}) {
  const row = document.createElement('div');
  row.className = 'col-label';
  const main = document.createElement('button');
  main.type = 'button';
  main.className = 'label-main';
  const chevron = expanded
    ? '<svg class="chevron" width="18" height="18" viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M7.41 8.59 12 13.17l4.59-4.58L18 10l-6 6-6-6z"/></svg>'
    : '<svg class="chevron" width="18" height="18" viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M8.59 16.59 13.17 12 8.59 7.41 10 6l6 6-6 6z"/></svg>';
  main.innerHTML = expandable
    ? `<span class="label-text"></span>${chevron}`
    : '<span class="label-text"></span>';
  main.querySelector('.label-text').textContent = title;
  if (expandable) main.addEventListener('click', onToggle);
  row.append(main);
  if (onAdd) {
    const add = document.createElement('button');
    add.type = 'button';
    add.className = 'col-add';
    add.textContent = '＋';
    add.title = '新建';
    add.addEventListener('click', onAdd);
    row.append(add);
  }
  return row;
}

function filterPanel({ title, subtitle, filters }) {
  const panel = document.createElement('section');
  panel.className = 'modules-panel';
  const header = document.createElement('div');
  header.className = 'modules-header';
  const titles = document.createElement('div');
  titles.className = 'modules-titles';
  const h = document.createElement('h2');
  h.textContent = title;
  const sub = document.createElement('p');
  sub.textContent = subtitle;
  titles.append(h, sub);
  // 占位与归类标题行右侧 ＋ 同宽，两块标题基线对齐
  const spacer = document.createElement('span');
  spacer.className = 'modules-create is-spacer';
  spacer.setAttribute('aria-hidden', 'true');
  header.append(titles, spacer);
  const grid = document.createElement('div');
  grid.className = 'filter-grid';
  for (const f of filters) grid.append(filterTile(f));
  panel.append(header, grid);
  return panel;
}

function filterTile(filter) {
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.className = 'filter-tile';
  const title = filterDisplayName(filter);
  const count = filter.countLabel ?? filter.itemCount ?? 0;
  const spec = iconForFilter(filter.code);
  btn.innerHTML = `
    <span class="nav-icon" style="background:${spec.bg}"><svg viewBox="0 0 24 24" fill="currentColor">${spec.svg}</svg></span>
    <span class="filter-tile-text">
      <span class="filter-tile-title"></span>
      <span class="filter-tile-count"></span>
    </span>
    <span class="arrow" aria-hidden="true">›</span>
  `;
  btn.querySelector('.filter-tile-title').textContent = title;
  btn.querySelector('.filter-tile-count').textContent = count;
  btn.addEventListener('click', () =>
    openMore({
      source: 'filter',
      key: filter.code,
      title,
      kind: kindForFilter(filter.code),
    }),
  );
  return btn;
}

function closeModuleMenus() {
  for (const el of document.querySelectorAll('.module-menu')) {
    el.hidden = true;
  }
}

function tagChip(tag, { muted = false } = {}) {
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.className = `tag-chip${muted ? ' is-muted' : ''}`;
  const name = String(tag.name || '').trim();
  const label = name.startsWith('#') ? name : `#${name}`;
  const count = Number(tag.itemCount || 0);
  btn.innerHTML =
    '<span class="tag-chip-bar" aria-hidden="true"></span><span class="tag-chip-name"></span>';
  btn.querySelector('.tag-chip-name').textContent = label;
  if (count > 0) {
    const c = document.createElement('span');
    c.className = 'tag-chip-count';
    c.textContent = String(count);
    btn.append(c);
  }
  btn.addEventListener('click', () =>
    openMore({
      source: 'tag',
      key: tag.id,
      title: tag.name,
      kind: 'unread',
    }),
  );
  if (!tag.isSystem) {
    btn.title = '右键删除';
    btn.addEventListener('contextmenu', (e) => {
      e.preventDefault();
      confirmDeleteTag(tag);
    });
  }
  return btn;
}

function moduleBlock({
  title,
  muted = false,
  hideTitle = false,
  tags,
  onOpenModule,
  onRenameModule,
  onAddTag,
  onDeleteModule,
}) {
  const block = document.createElement('div');
  block.className = `module-case${muted ? ' is-ungrouped' : ''}`;

  const body = document.createElement('div');
  body.className = 'module-case-body';

  // 未归类：不显示标题，只留标签（仍可拖回此处）
  if (!hideTitle) {
    const head = document.createElement('div');
    head.className = 'module-head';

    if (onOpenModule) {
      const titleBtn = document.createElement('button');
      titleBtn.type = 'button';
      titleBtn.className = 'module-title is-link';
      titleBtn.innerHTML =
        '<span class="module-title-text"></span><span class="module-chevron" aria-hidden="true">›</span>';
      titleBtn.querySelector('.module-title-text').textContent = title;
      titleBtn.addEventListener('click', onOpenModule);
      head.append(titleBtn);
    } else {
      const titleEl = document.createElement('div');
      titleEl.className = 'module-title';
      titleEl.textContent = title;
      head.append(titleEl);
    }

    if (onRenameModule || onAddTag || onDeleteModule) {
      const wrap = document.createElement('div');
      wrap.className = 'module-more-wrap';
      const moreBtn = document.createElement('button');
      moreBtn.type = 'button';
      moreBtn.className = 'module-more';
      moreBtn.title = '更多';
      moreBtn.setAttribute('aria-label', '更多');
      moreBtn.textContent = '⋯';
      const menu = document.createElement('div');
      menu.className = 'module-menu';
      menu.hidden = true;
      if (onRenameModule) {
        const rename = document.createElement('button');
        rename.type = 'button';
        rename.textContent = '修改名称';
        rename.addEventListener('click', () => {
          menu.hidden = true;
          onRenameModule();
        });
        menu.append(rename);
      }
      if (onAddTag) {
        const add = document.createElement('button');
        add.type = 'button';
        add.textContent = '添加标签';
        add.addEventListener('click', () => {
          menu.hidden = true;
          onAddTag();
        });
        menu.append(add);
      }
      if (onDeleteModule) {
        const del = document.createElement('button');
        del.type = 'button';
        del.className = 'is-danger';
        del.textContent = '删除归类';
        del.addEventListener('click', () => {
          menu.hidden = true;
          onDeleteModule();
        });
        menu.append(del);
      }
      moreBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        const open = menu.hidden;
        closeModuleMenus();
        menu.hidden = !open;
      });
      wrap.append(moreBtn, menu);
      head.append(wrap);
    }

    body.append(head);
  }

  const chips = document.createElement('div');
  chips.className = 'tag-chip-wrap';
  const list = Array.isArray(tags) ? tags : [];
  if (!list.length) {
    const empty = document.createElement('p');
    empty.className = 'module-empty';
    empty.textContent = hideTitle
      ? '没有归类的标签会出现在这里'
      : '暂无标签';
    chips.append(empty);
  } else {
    for (const tag of list) chips.append(tagChip(tag, { muted }));
  }
  body.append(chips);
  block.append(body);
  return block;
}

function renderCollection() {
  const s = collectionState;
  collectionBody.replaceChildren();
  closeModuleMenus();

  if (s.loading && !s.filters.length && !s.modules.length && !s.ungrouped.length) {
    const msg = document.createElement('p');
    msg.className = 'list-msg';
    msg.textContent = '加载中…';
    collectionBody.append(msg);
    return;
  }
  if (s.error && !s.filters.length) {
    const card = document.createElement('div');
    card.className = 'error-card';
    card.innerHTML = '<div></div>';
    card.querySelector('div').textContent = s.error;
    const retry = document.createElement('button');
    retry.type = 'button';
    retry.textContent = '重试';
    retry.addEventListener('click', () => loadCollection());
    card.append(retry);
    collectionBody.append(card);
    return;
  }

  const filters = collectionFilters(s.filters);
  if (filters.length) {
    collectionBody.append(
      filterPanel({
        title: '系统分类',
        subtitle: '按状态快速筛选收藏',
        filters,
      }),
    );
  }

  const panel = document.createElement('section');
  panel.className = 'modules-panel';

  const header = document.createElement('div');
  header.className = 'modules-header';
  const titles = document.createElement('div');
  titles.className = 'modules-titles';
  const h = document.createElement('h2');
  h.textContent = '归类标签';
  const sub = document.createElement('p');
  sub.textContent = '分格摆放 · 右键可删标签';
  titles.append(h, sub);
  const createMod = document.createElement('button');
  createMod.type = 'button';
  createMod.className = 'modules-create';
  createMod.title = '新建归类';
  createMod.setAttribute('aria-label', '新建归类');
  createMod.textContent = '＋';
  createMod.addEventListener('click', openCreateModule);
  header.append(titles, createMod);
  panel.append(header);

  const cases = document.createElement('div');
  cases.className = 'module-cases';
  cases.append(
    moduleBlock({
      title: '未归类',
      muted: true,
      hideTitle: true,
      tags: s.ungrouped,
    }),
  );
  for (const mod of s.modules) {
    cases.append(
      moduleBlock({
        title: mod.name,
        tags: mod.tags || [],
        onOpenModule: () =>
          openMore({
            source: 'module',
            key: mod.id,
            title: mod.name,
            kind: 'unread',
          }),
        onRenameModule: () => openRenameModule(mod),
        onAddTag: () => openCreateTag({ moduleId: mod.id }),
        onDeleteModule: () => confirmDeleteModule(mod),
      }),
    );
  }
  panel.append(cases);
  collectionBody.append(panel);
}

async function loadCollection({ quiet = false } = {}) {
  const empty =
    !collectionState.filters.length &&
    !collectionState.modules.length &&
    !collectionState.ungrouped.length;
  if (!quiet || empty) {
    collectionState.loading = true;
    collectionState.error = null;
    renderCollection();
  }
  try {
    const [modulesRes, filtersRes] = await Promise.all([
      listTagModules(),
      fetchSystemFilters(),
    ]);
    collectionState.modules = modulesRes.modules || [];
    collectionState.ungrouped = modulesRes.ungrouped || [];
    collectionState.filters = filtersRes.filters || [];
    collectionState.mediaFilters = filtersRes.mediaFilters || [];
    collectionState.loading = false;
    collectionState.error = null;
    renderCollection();
  } catch (err) {
    if (await handleAuthError(err)) return;
    collectionState.loading = false;
    if (!quiet) collectionState.error = err.message || '加载失败';
    renderCollection();
  }
}

function hideSheets() {
  $('sheet-add').hidden = true;
  $('sheet-name').hidden = true;
  $('sheet-pick').hidden = true;
  $('dialog').hidden = true;
}

function openOverlay(mode) {
  hideSheets();
  overlayEl.hidden = false;
  overlayEl.classList.toggle('is-dialog', mode === 'dialog');
  if (mode === 'add') $('sheet-add').hidden = false;
  if (mode === 'name') $('sheet-name').hidden = false;
  if (mode === 'pick') $('sheet-pick').hidden = false;
  if (mode === 'dialog') $('dialog').hidden = false;
}

function closeOverlay({ cancel = true } = {}) {
  if (overlayBusy) return;
  overlayEl.hidden = true;
  hideSheets();
  if (cancel && dialogResolver) {
    const resolve = dialogResolver;
    dialogResolver = null;
    resolve(false);
  }
  nameSubmit = null;
  nameAfterClose = null;
}

function confirmDialog({
  title,
  message,
  confirmLabel = '确定',
  danger = false,
}) {
  return new Promise((resolve) => {
    dialogResolver = resolve;
    $('dialog-title').textContent = title;
    $('dialog-msg').textContent = message;
    $('dialog-ok').textContent = confirmLabel;
    $('dialog-ok').classList.toggle('is-danger', danger);
    openOverlay('dialog');
  });
}

function finishDialog(ok) {
  const resolve = dialogResolver;
  dialogResolver = null;
  overlayBusy = false;
  overlayEl.hidden = true;
  hideSheets();
  if (resolve) resolve(ok);
}

async function openAddLink() {
  await syncCurrentTab();
  const url = canSaveUrl(currentTab?.url) ? currentTab.url : '';
  addUrl.value = url;
  addError.hidden = Boolean(url);
  addError.textContent = url ? '' : '当前页不是网页，无法收藏';
  addHint.hidden = true;
  addSave.disabled = !url;
  addSave.textContent = '保存';
  openOverlay('add');
}

async function submitAddLink() {
  if (addSaving) return;
  const url = addUrl.value.trim();
  if (!canSaveUrl(url)) {
    addError.hidden = false;
    addError.textContent = '请输入有效的 http(s) 链接';
    return;
  }
  addSaving = true;
  overlayBusy = true;
  addSave.disabled = true;
  addSave.textContent = '保存中…';
  addHint.hidden = false;
  addError.hidden = true;
  try {
    const result = await saveUrl(url);
    overlayBusy = false;
    addSaving = false;
    closeOverlay({ cancel: false });
    const existed = Boolean(result.existed);
    toast(result.message || (existed ? '该链接已收藏' : '已收藏'));
    const item = result.item;
    if (item) openItemLink(item);
    loadHome();
  } catch (err) {
    overlayBusy = false;
    addSaving = false;
    addSave.disabled = false;
    addSave.textContent = '保存';
    addHint.hidden = true;
    if (await handleAuthError(err)) {
      closeOverlay({ cancel: false });
      return;
    }
    addError.hidden = false;
    addError.textContent = err.message || '保存失败';
  }
}

function openNameSheet({
  title,
  label,
  placeholder,
  submitLabel,
  initialValue = '',
  onSubmit,
  afterClose = null,
}) {
  $('name-title').textContent = title;
  $('name-label').textContent = label;
  nameInput.placeholder = placeholder;
  nameInput.value = initialValue || '';
  nameError.hidden = true;
  nameSave.textContent = submitLabel || '创建';
  nameSave.disabled = false;
  nameSubmit = onSubmit;
  nameAfterClose = afterClose;
  openOverlay('name');
  nameInput.focus();
  nameInput.select();
}

async function submitNameSheet() {
  if (!nameSubmit || overlayBusy) return;
  const name = nameInput.value.trim();
  overlayBusy = true;
  nameSave.disabled = true;
  try {
    const created = await nameSubmit(name);
    const after = nameAfterClose;
    overlayBusy = false;
    nameSubmit = null;
    nameAfterClose = null;
    if (after) {
      after(created);
      return;
    }
    closeOverlay({ cancel: false });
  } catch (err) {
    overlayBusy = false;
    nameSave.disabled = false;
    if (await handleAuthError(err)) {
      closeOverlay({ cancel: false });
      return;
    }
    nameError.hidden = false;
    nameError.textContent = err.message || '创建失败';
  }
}

function openCreateTag({ afterCreate, moduleId } = {}) {
  openNameSheet({
    title: '新建标签',
    label: '名称',
    placeholder: '请输入标签名称',
    onSubmit: async (name) => {
      if (!name) throw new Error('请输入标签名称');
      if (name.length > 64) throw new Error('名称最多 64 个字');
      const res = await createTag(name, {
        moduleId: moduleId == null ? undefined : moduleId,
      });
      if (!afterCreate) {
        await loadCollection({ quiet: true });
        toast(`已创建标签「${res.tag?.name || name}」`);
      }
      return res.tag;
    },
    afterClose: afterCreate,
  });
}

function openCreateModule() {
  openNameSheet({
    title: '新建归类',
    label: '名称',
    placeholder: '请输入归类名称',
    onSubmit: async (name) => {
      if (!name) throw new Error('请输入归类名称');
      if (name.length > 64) throw new Error('名称最多 64 个字');
      const res = await createTagModule(name);
      await loadCollection({ quiet: true });
      toast(`已创建归类「${res.module?.name || name}」`);
      return res.module;
    },
  });
}

function openRenameModule(mod) {
  openNameSheet({
    title: '修改名称',
    label: '名称',
    placeholder: '请输入归类名称',
    submitLabel: '保存',
    initialValue: mod.name || '',
    onSubmit: async (name) => {
      if (!name) throw new Error('请输入归类名称');
      if (name.length > 64) throw new Error('名称最多 64 个字');
      const res = await renameTagModule(mod.id, name);
      await loadCollection({ quiet: true });
      toast(`已修改为「${res.module?.name || name}」`);
      return res.module;
    },
  });
}

async function confirmDeleteTag(tag) {
  const ok = await confirmDialog({
    title: '删除标签',
    message: `确定删除标签「${tag.name}」？仅解除关联，不会删除条目。`,
    confirmLabel: '删除',
    danger: true,
  });
  if (!ok) return;
  try {
    await deleteTag(tag.id);
    await loadCollection({ quiet: true });
    toast(`已删除标签「${tag.name}」`);
  } catch (err) {
    if (await handleAuthError(err)) return;
    toast(err.message || '删除失败');
  }
}

async function confirmDeleteModule(mod) {
  const ok = await confirmDialog({
    title: '删除归类',
    message: `确定删除归类「${mod.name}」？组内标签会回到未归类，不会删除标签。`,
    confirmLabel: '删除',
    danger: true,
  });
  if (!ok) return;
  try {
    await deleteTagModule(mod.id);
    await loadCollection({ quiet: true });
    toast(`已删除归类「${mod.name}」`);
  } catch (err) {
    if (await handleAuthError(err)) return;
    toast(err.message || '删除失败');
  }
}

async function logout() {
  const ok = await confirmDialog({
    title: '退出登录？',
    message: '退出后需重新验证手机号登录。',
    confirmLabel: '退出',
    danger: true,
  });
  if (!ok) return;
  await clearSession();
  viewStack = [];
  collectionState = emptyCollection();
  more = emptyMore();
  searchState = emptySearch();
  showView('login');
}

async function openDetail(item) {
  if (currentView !== 'detail') pushView('detail');
  stopDetailPoll();
  hideDetailMenu();
  detailState = { item, error: null, loading: !item };
  detailMore.disabled = !item;
  renderDetail();
  try {
    const itemRes = await fetchItem(item.id);
    if (detailState.item?.id !== item.id) return;
    detailState.item = itemRes.item || item;
    detailState.loading = false;
    detailState.error = null;
    detailMore.disabled = false;
    renderDetail();
    syncDetailPolling(detailState.item);
  } catch (err) {
    if (await handleAuthError(err)) return;
    detailState.loading = false;
    if (!detailState.item) detailState.error = err.message || '加载失败';
    else toast(err.message || '加载详情失败');
    renderDetail();
  }
}

function stopDetailPoll() {
  if (detailPoll) {
    clearInterval(detailPoll);
    detailPoll = null;
  }
}

function syncDetailPolling(item) {
  stopDetailPoll();
  if (!item || item.status !== 'pending') return;
  detailPoll = setInterval(() => pollDetailOnce(item.id), 1600);
}

async function pollDetailOnce(id) {
  if (currentView !== 'detail' || detailState.item?.id !== id) {
    stopDetailPoll();
    return;
  }
  try {
    const res = await fetchItem(id);
    if (currentView !== 'detail' || detailState.item?.id !== id) return;
    detailState.item = res.item || detailState.item;
    renderDetail();
    if (detailState.item?.status !== 'pending') stopDetailPoll();
  } catch {
    // 轮询失败不打断页面
  }
}

function hideDetailMenu() {
  if (detailMenu) detailMenu.hidden = true;
}

function toggleDetailMenu() {
  if (detailMore.disabled) return;
  detailMenu.hidden = !detailMenu.hidden;
}

function renderDetail() {
  const item = detailState.item;
  detailBody.replaceChildren();
  detailMore.disabled = !item;

  if (detailState.loading && !item) {
    const msg = document.createElement('p');
    msg.className = 'list-msg';
    msg.textContent = '加载中…';
    detailBody.append(msg);
    return;
  }
  if (detailState.error && !item) {
    const msg = document.createElement('p');
    msg.className = 'list-msg';
    msg.textContent = detailState.error;
    detailBody.append(msg);
    return;
  }
  if (!item) return;

  const title = document.createElement('h2');
  title.className = 'detail-title';
  title.textContent = itemTitle(item);

  const meta = document.createElement('p');
  meta.className = 'detail-meta';
  meta.textContent = [platformLabel(item.platform, item.canonicalUrl || item.url), formatDateTime(item.createdAt)]
    .filter(Boolean)
    .join(' · ');

  const chip = document.createElement('span');
  const status = item.status || 'pending';
  chip.className = `chip-status ${
    status === 'success' ? 'chip-success' : status === 'failed' ? 'chip-failed' : 'chip-pending'
  }`;
  chip.textContent =
    status === 'success' ? '解析完成' : status === 'failed' ? '解析失败' : '正在解析…';

  const url = document.createElement('a');
  url.className = 'detail-url';
  url.href = itemLink(item) || '#';
  url.target = '_blank';
  url.rel = 'noopener';
  url.textContent = item.url || '';

  detailBody.append(title, meta, chip);

  const detailTags = tagsLine(item.tags);
  if (detailTags) {
    const tagsEl = document.createElement('p');
    tagsEl.className = 'detail-tags';
    tagsEl.textContent = detailTags;
    detailBody.append(tagsEl);
  }

  detailBody.append(url);

  if (status === 'pending') {
    const card = document.createElement('div');
    card.className = 'detail-card';
    card.innerHTML =
      '<div class="skel w-lg"></div><div class="skel w-md"></div><div class="skel w-sm"></div><div class="skel w-lg gap"></div><div class="skel w-md"></div>';
    detailBody.append(card);
    return;
  }

  if (status === 'failed') {
    const card = document.createElement('div');
    card.className = 'detail-card';
    const h = document.createElement('h3');
    h.textContent = '无法解析该链接的正文';
    const p = document.createElement('p');
    p.textContent = item.errorMessage || '请稍后重试。也可打开原文查看。';
    const retry = document.createElement('button');
    retry.type = 'button';
    retry.className = 'primary';
    retry.textContent = '重试解析';
    retry.addEventListener('click', reparseCurrent);
    card.append(h, p, retry);
    detailBody.append(card);
    return;
  }

  const card = document.createElement('div');
  card.className = 'detail-card';
  const cover = previewImages(item)[0];
  if (cover) {
    const img = document.createElement('img');
    img.className = 'detail-cover';
    img.src = cover;
    img.alt = '';
    img.referrerPolicy = 'no-referrer';
    img.addEventListener('error', () => img.remove());
    card.append(img);
  }
  const label = document.createElement('div');
  label.className = 'detail-lede-label';
  label.textContent = '正文';
  const lede = document.createElement('p');
  lede.className = 'detail-lede';
  lede.textContent = stripPreviewMd(previewText(item) || '正文已解析。');
  card.append(label, lede);
  detailBody.append(card);
}

async function reparseCurrent() {
  const item = detailState.item;
  if (!item) return;
  try {
    const res = await reparseItem(item.id);
    detailState.item = res.item || { ...item, status: 'pending' };
    renderDetail();
    syncDetailPolling(detailState.item);
  } catch (err) {
    if (await handleAuthError(err)) return;
    toast(err.message || '重试失败');
  }
}

async function copyDetailLink() {
  hideDetailMenu();
  const item = detailState.item;
  const link = item ? itemLink(item) : '';
  if (!link) {
    toast('暂无链接');
    return;
  }
  try {
    await navigator.clipboard.writeText(link);
    toast('链接已复制');
  } catch {
    toast('复制失败');
  }
}

function renderPickList(rows) {
  const list = $('pick-list');
  list.replaceChildren();
  for (const row of rows) list.append(row);
}

async function openTagPicker() {
  hideDetailMenu();
  const item = detailState.item;
  if (!item) return;
  $('pick-title').textContent = '选择标签';
  const saveBtnEl = $('pick-save');
  saveBtnEl.hidden = false;
  saveBtnEl.disabled = false;
  saveBtnEl.textContent = '保存';
  openOverlay('pick');

  let selected = new Set();
  let all = [];

  const draw = () => {
    const rows = [];
    const add = document.createElement('button');
    add.type = 'button';
    add.className = 'pick-row';
    add.innerHTML = '<span class="name">＋ 新建标签</span>';
    add.addEventListener('click', () => {
      openCreateTag({
        afterCreate: (tag) => {
          if (!tag) return;
          all = [...all, tag];
          selected.add(tag.id);
          openOverlay('pick');
          $('pick-title').textContent = '选择标签';
          saveBtnEl.hidden = false;
          draw();
        },
      });
    });
    rows.push(add);

    const chips = document.createElement('div');
    chips.className = 'chip-wrap';
    const userTags = all.filter((t) => !t.isSystem);
    if (!userTags.length) {
      const empty = document.createElement('p');
      empty.className = 'list-msg';
      empty.style.margin = '8px 0';
      empty.textContent = '还没有标签，先新建一个';
      rows.push(empty);
    } else {
      for (const tag of userTags) {
        const chip = document.createElement('button');
        chip.type = 'button';
        chip.className = `chip${selected.has(tag.id) ? ' is-on' : ''}`;
        chip.textContent = tag.name;
        chip.addEventListener('click', () => {
          if (selected.has(tag.id)) selected.delete(tag.id);
          else selected.add(tag.id);
          draw();
        });
        chips.append(chip);
      }
      rows.push(chips);
    }
    renderPickList(rows);
  };

  pickSave = async () => {
    overlayBusy = true;
    saveBtnEl.disabled = true;
    try {
      await setItemTags(item.id, [...selected]);
      overlayBusy = false;
      saveBtnEl.disabled = false;
      closeOverlay({ cancel: false });
      toast('标签已更新');
    } catch (err) {
      overlayBusy = false;
      saveBtnEl.disabled = false;
      if (await handleAuthError(err)) {
        closeOverlay({ cancel: false });
        return;
      }
      toast(err.message || '保存失败');
    }
  };

  try {
    const [tagsRes, currentRes] = await Promise.all([
      listTags(),
      listItemTags(item.id),
    ]);
    all = tagsRes.tags || [];
    selected = new Set(
      (currentRes.tags || []).filter((t) => !t.isSystem).map((t) => t.id),
    );
    draw();
  } catch (err) {
    pickSave = null;
    if (await handleAuthError(err)) {
      closeOverlay({ cancel: false });
      return;
    }
    toast(err.message || '加载标签失败');
    closeOverlay({ cancel: false });
  }
}

async function deleteCurrentItem() {
  hideDetailMenu();
  const item = detailState.item;
  if (!item) return;
  const ok = await confirmDialog({
    title: '删除这条收藏？',
    message: '删除后无法恢复。',
    confirmLabel: '删除',
    danger: true,
  });
  if (!ok) return;
  try {
    await deleteItem(item.id);
    toast('已删除');
    popView();
  } catch (err) {
    if (await handleAuthError(err)) return;
    toast(err.message || '删除失败');
  }
}

async function render() {
  const session = await getSession();
  if (!session) {
    showView('login');
    return;
  }
  await showHome();
}

function validPhone(phone) {
  return /^1\d{10}$/.test(phone);
}

function startCountdown() {
  countdown = 60;
  sendBtn.disabled = true;
  sendBtn.textContent = `${countdown}s`;
  timer = setInterval(() => {
    countdown -= 1;
    if (countdown <= 0) {
      clearInterval(timer);
      sendBtn.disabled = false;
      sendBtn.textContent = '获取验证码';
      return;
    }
    sendBtn.textContent = `${countdown}s`;
  }, 1000);
}

sendBtn.addEventListener('click', async () => {
  const phone = phoneInput.value.trim();
  if (!agreedEl.checked) {
    toast('请先勾选同意用户协议和隐私政策');
    return;
  }
  if (!validPhone(phone)) {
    toast('请输入正确的手机号');
    return;
  }
  sendBtn.disabled = true;
  try {
    await sendCode(phone);
    toast('验证码已发送');
    startCountdown();
  } catch (err) {
    sendBtn.disabled = false;
    toast(err.message);
  }
});

loginBtn.addEventListener('click', async () => {
  const phone = phoneInput.value.trim();
  const code = codeInput.value.trim();
  if (!agreedEl.checked) {
    toast('请先勾选同意用户协议和隐私政策');
    return;
  }
  if (!validPhone(phone)) {
    toast('请输入正确的手机号');
    return;
  }
  if (!code) {
    toast('请输入验证码');
    return;
  }
  loginBtn.disabled = true;
  loginBtn.textContent = '登录中…';
  try {
    await login(phone, code);
    await showHome();
    toast('登录成功');
  } catch (err) {
    toast(err.message);
  } finally {
    loginBtn.disabled = false;
    loginBtn.textContent = '登录';
  }
});

function openSearch() {
  pushView('search');
  searchInput.value = '';
  searchState = emptySearch();
  renderSearch();
  searchInput.focus();
}

saveBtn.addEventListener('click', () => openAddLink());
$('tab-search').addEventListener('click', openSearch);
$('home-avatar').addEventListener('click', logout);
$('collection-avatar').addEventListener('click', logout);
$('search-cancel').addEventListener('click', popView);
searchClear.addEventListener('click', () => {
  searchInput.value = '';
  searchState = emptySearch();
  renderSearch();
  searchInput.focus();
});
$('more-back').addEventListener('click', popView);
$('detail-back').addEventListener('click', popView);
$('detail-more').addEventListener('click', (e) => {
  e.stopPropagation();
  toggleDetailMenu();
});
$('detail-copy').addEventListener('click', copyDetailLink);
$('detail-tags').addEventListener('click', openTagPicker);
$('detail-delete').addEventListener('click', deleteCurrentItem);
$('detail-menu').addEventListener('click', (e) => e.stopPropagation());
document.addEventListener('click', () => {
  hideDetailMenu();
  closeModuleMenus();
});

searchInput.addEventListener('input', () => {
  clearTimeout(searchTimer);
  const q = searchInput.value.trim();
  if (!q) {
    searchState = emptySearch();
    renderSearch();
    return;
  }
  searchTimer = setTimeout(() => runSearch({ reset: true }), 320);
});
searchInput.addEventListener('keydown', (e) => {
  if (e.key !== 'Enter') return;
  clearTimeout(searchTimer);
  runSearch({ reset: true });
  searchInput.blur();
});

for (const btn of tabbarEl.querySelectorAll('.tab-item')) {
  btn.addEventListener('click', () => switchTab(btn.dataset.tab));
}

$('add-save').addEventListener('click', submitAddLink);
nameSave.addEventListener('click', submitNameSheet);
nameInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') submitNameSheet();
});
$('pick-save').addEventListener('click', () => {
  if (pickSave) pickSave();
});
$('dialog-cancel').addEventListener('click', () => finishDialog(false));
$('dialog-ok').addEventListener('click', () => finishDialog(true));

$('roam-player-close').addEventListener('click', closeRoamPlayer);

function onRoamPointerDown(e) {
  if (roamSwipe.settling || roamSwipe.active) return;
  if (e.button != null && e.button !== 0) return;
  if (e.target.closest('button')) return;
  if (roamPlayer.index >= roamPlayer.snippets.length) return;
  // 避免点按/轻拖时浏览器把正文整段选中
  const sel = window.getSelection?.();
  if (sel?.rangeCount) sel.removeAllRanges();
  roamSwipe.active = true;
  roamSwipe.mode = null;
  roamSwipe.pointerId = e.pointerId;
  roamSwipe.startX = e.clientX;
  roamSwipe.startY = e.clientY;
  roamSwipe.lastX = e.clientX;
  roamSwipe.lastT = performance.now();
  roamSwipe.ox = 0;
  roamSwipe.oy = 0;
  roamSwipe.vx = 0;
  try {
    roamPlayerDeck.setPointerCapture(e.pointerId);
  } catch {
    // ignore
  }
}

function onRoamPointerMove(e) {
  if (!roamSwipe.active || roamSwipe.settling) return;
  if (roamSwipe.pointerId != null && e.pointerId !== roamSwipe.pointerId) return;

  const dx = e.clientX - roamSwipe.startX;
  const dy = e.clientY - roamSwipe.startY;

  if (!roamSwipe.mode) {
    if (Math.hypot(dx, dy) < 8) return;
    const inScroll = Boolean(e.target.closest?.('.roam-quote-scroll'));
    if (inScroll && Math.abs(dy) > Math.abs(dx)) {
      roamSwipe.mode = 'scroll';
      roamSwipe.active = false;
      return;
    }
    roamSwipe.mode = 'swipe';
  }
  if (roamSwipe.mode !== 'swipe') return;

  e.preventDefault();
  const now = performance.now();
  const dt = Math.max(1, now - roamSwipe.lastT);
  roamSwipe.vx = ((e.clientX - roamSwipe.lastX) / dt) * 1000;
  roamSwipe.lastX = e.clientX;
  roamSwipe.lastT = now;
  roamSwipe.ox = dx;
  roamSwipe.oy = dy;
  applyRoamSwipeTransform(dx, dy);
}

async function onRoamPointerUp(e) {
  if (roamSwipe.pointerId != null && e.pointerId !== roamSwipe.pointerId) return;
  const wasSwipe = roamSwipe.mode === 'swipe';
  const ox = roamSwipe.ox;
  const oy = roamSwipe.oy;
  const vx = roamSwipe.vx;
  roamSwipe.active = false;
  roamSwipe.mode = null;
  roamSwipe.pointerId = null;

  if (!wasSwipe || roamSwipe.settling) return;

  const w = roamPlayerDeck.clientWidth || 320;
  // 对齐 App：位移 > 22% 宽 或 横向速度 > 900
  const pass = Math.abs(ox) > w * 0.22 || Math.abs(vx) > 900;
  if (!pass) {
    if (Math.hypot(ox, oy) > 8) roamPlayer.suppressClick = true;
    await animateRoamSwipeTo(0, 0, 200);
    clearRoamSwipeTransform();
    roamSwipe.ox = 0;
    roamSwipe.oy = 0;
    return;
  }
  const dir = (ox === 0 ? vx : ox) >= 0 ? 1 : -1;
  await dismissRoamFront(dir);
}

roamPlayerDeck.addEventListener('pointerdown', onRoamPointerDown);
roamPlayerDeck.addEventListener('pointermove', onRoamPointerMove, { passive: false });
roamPlayerDeck.addEventListener('pointerup', onRoamPointerUp);
roamPlayerDeck.addEventListener('pointercancel', onRoamPointerUp);
roamPlayerDeck.addEventListener(
  'wheel',
  (e) => {
    if (roamSwipe.settling || roamSwipe.active) return;
    if (roamPlayer.index >= roamPlayer.snippets.length) return;
    if (Math.abs(e.deltaX) < 24 && e.deltaY <= 24) return;
    const scroll = roamPlayerDeck.querySelector('.roam-quote-scroll');
    if (
      Math.abs(e.deltaY) >= Math.abs(e.deltaX) &&
      scroll &&
      scroll.scrollHeight > scroll.clientHeight + 2
    ) {
      const atBottom =
        scroll.scrollTop + scroll.clientHeight >= scroll.scrollHeight - 4;
      if (!atBottom) return;
    }
    e.preventDefault();
    const dir = e.deltaX !== 0 ? (e.deltaX > 0 ? 1 : -1) : 1;
    dismissRoamFront(dir);
  },
  { passive: false },
);

for (const btn of document.querySelectorAll('[data-close-overlay]')) {
  btn.addEventListener('click', () => closeOverlay());
}
overlayEl.addEventListener('click', (e) => {
  if (e.target === overlayEl) closeOverlay();
});
for (const sheet of overlayEl.querySelectorAll('.sheet, .dialog')) {
  sheet.addEventListener('click', (e) => e.stopPropagation());
}

chrome.tabs.onActivated.addListener(() => {
  syncCurrentTab();
});
chrome.tabs.onUpdated.addListener((_id, info) => {
  if (info.status === 'complete' || info.url) syncCurrentTab();
});

window.addEventListener('scroll', () => {
  const remain =
    document.documentElement.scrollHeight - window.scrollY - window.innerHeight;
  if (remain >= 120) return;
  if (!moreEl.hidden) loadMorePage();
  if (!searchEl.hidden) runSearch({ reset: false });
});

render();
