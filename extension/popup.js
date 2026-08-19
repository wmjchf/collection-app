import {
  canSaveUrl,
  clearSession,
  createFolder,
  createTag,
  deleteFolder,
  deleteTag,
  emptyTrash,
  fetchHome,
  fetchItem,
  fetchSystemFilters,
  getSession,
  listFolderItems,
  listFolders,
  listItems,
  listTagItems,
  listTags,
  login,
  listItemTags,
  patchItem,
  purgeItem,
  reparseItem,
  restoreItem,
  saveUrl,
  searchItems,
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
const settingsEl = $('settings');
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
const searchList = $('search-list');
const searchStatus = $('search-status');
const settingsBody = $('settings-body');
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

function platformLabel(platform) {
  const p = String(platform || '').trim();
  return p || 'web';
}

const EMPTY_ICON = `<svg viewBox="0 0 24 24" fill="none" stroke="#C5CAD3" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/></svg>`;

const ICON = {
  unread: { bg: '#5B8FF9', svg: '<circle cx="12" cy="12" r="4.5" fill="none" stroke="currentColor" stroke-width="2.4"/><circle cx="12" cy="12" r="1.6"/>' },
  all: { bg: '#6E788C', svg: '<path d="M5 7h14v1.8H5V7zm0 4.1h14v1.8H5v-1.8zm0 4.1h14V17H5v-1.8z"/>' },
  today: { bg: '#FF9F43', svg: '<rect x="4.5" y="6" width="15" height="13.5" rx="2"/><path d="M8 4.5v3M16 4.5v3M4.5 10h15" fill="none" stroke="#fff" stroke-width="1.6"/>' },
  starred: { bg: '#FFC43D', svg: '<path d="M12 4.2 14.1 9l5.2.4-4 3.4 1.2 5.1L12 15.4 7.5 17.9l1.2-5.1-4-3.4 5.2-.4z"/>' },
  parsed: { bg: '#56CC8C', svg: '<path d="M7 4.5h7l4 4V19.5H7z"/><path d="M14 4.5V9h4.5" fill="none" stroke="#fff" stroke-width="1.4"/>' },
  annotated: { bg: '#A270F5', svg: '<path d="M5 18.5 7.2 12 16 3.2l4.8 4.8L12 16.8z"/><path d="M14.2 5l4.8 4.8" fill="none" stroke="#fff" stroke-width="1.2"/>' },
  recent_read: { bg: '#40BAC4', svg: '<circle cx="12" cy="12" r="7.5" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 8v4.5l3 1.8" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>' },
  archived: { bg: '#96A0AF', svg: '<path d="M4.5 7.5h15v3h-15z"/><path d="M6 10.5h12V19H6z"/>' },
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
  settings: settingsEl,
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

function emptyMore() {
  return {
    source: 'filter',
    key: '',
    kind: 'unread',
    items: [],
    total: 0,
    loading: false,
  };
}

function emptySearch() {
  return { q: '', items: [], total: 0, loading: false };
}

function emptyCollection() {
  return {
    folders: [],
    tags: [],
    filters: [],
    others: [],
    systemExpanded: true,
    foldersExpanded: true,
    tagsExpanded: true,
    othersExpanded: true,
    loading: false,
    error: null,
  };
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

function subtitleFor(kind, item) {
  if (kind === 'annotated') {
    return `${item.annotationCount || 0} 处标注`;
  }
  if (kind === 'recent') {
    return formatRelativeTime(item.lastReadAt || item.updatedAt);
  }
  return [platformLabel(item.platform), formatDay(item.createdAt)]
    .filter(Boolean)
    .join(' · ');
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
  const p = (item.platform || '').toLowerCase();
  if (['kr36', 'web', 'zhihu', 'zaker', 'bilibili'].includes(p)) return false;
  if (p === 'weixin' || p === 'wechat') return true;
  if (isDouyinNoteOrSlides(item)) return true;
  if (p === 'douyin') return !hasVideo(item);
  if (p === 'xiaohongshu' || p === 'jike' || p === 'weibo') {
    return !(item.videoUrl || '').trim();
  }
  return images.length >= 2;
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
  const sub = document.createElement('p');
  sub.className = 'card-sub';
  sub.textContent = subtitleFor(kind, item);
  body.append(title, sub);
  card.append(body);
  card.addEventListener('click', () => openDetail(item));
  return card;
}

function trashCardEl(item) {
  const card = document.createElement('div');
  card.className = 'card trash-card';
  const main = document.createElement('div');
  main.className = 'trash-main';
  main.append(coverEl(item.coverImageUrl));
  const body = document.createElement('div');
  body.className = 'card-body';
  const title = document.createElement('p');
  title.className = 'card-title';
  title.textContent = itemTitle(item);
  const sub = document.createElement('p');
  sub.className = 'card-sub';
  const day = formatDay(item.deletedAt);
  sub.textContent = day ? `删除于 ${day}` : '已删除';
  body.append(title, sub);
  main.append(body);
  const actions = document.createElement('div');
  actions.className = 'trash-actions';
  const restore = document.createElement('button');
  restore.type = 'button';
  restore.className = 'trash-restore';
  restore.textContent = '恢复';
  restore.addEventListener('click', () => restoreTrashItem(item));
  const purge = document.createElement('button');
  purge.type = 'button';
  purge.className = 'trash-purge';
  purge.textContent = '彻底删除';
  purge.addEventListener('click', () => purgeTrashItem(item));
  actions.append(restore, purge);
  card.append(main, actions);
  return card;
}

function emptyCard(text) {
  const el = document.createElement('div');
  el.className = 'empty-card';
  el.innerHTML = `${EMPTY_ICON}<span></span>`;
  el.querySelector('span').textContent = text;
  return el;
}

function sectionEl({ title, emptyText, items, kind, filter, moreTitleText }) {
  const wrap = document.createElement('section');
  const head = document.createElement('div');
  head.className = 'section-head';
  const h2 = document.createElement('h2');
  h2.textContent = title;
  const moreBtn = document.createElement('button');
  moreBtn.type = 'button';
  moreBtn.className = 'more';
  moreBtn.textContent = '查看更多 ›';
  moreBtn.addEventListener('click', () =>
    openMore({
      source: 'filter',
      key: filter,
      title: moreTitleText,
      kind,
    }),
  );
  head.append(h2, moreBtn);
  wrap.append(head);
  const cards = document.createElement('div');
  cards.className = 'section-cards';
  if (!items.length) {
    cards.append(emptyCard(emptyText));
  } else {
    for (const item of items) cards.append(cardEl(item, kind));
  }
  wrap.append(cards);
  return wrap;
}

function renderHome(data) {
  homeBody.replaceChildren();
  if (!data) {
    const msg = document.createElement('p');
    msg.className = 'list-msg';
    msg.textContent = '加载中…';
    homeBody.append(msg);
    return;
  }
  homeBody.append(
    sectionEl({
      title: '未读',
      emptyText: '暂无未读',
      items: data.unread?.items || [],
      kind: 'unread',
      filter: 'unread',
      moreTitleText: '未读',
    }),
    sectionEl({
      title: '标注',
      emptyText: '暂无标注',
      items: data.annotated?.items || [],
      kind: 'annotated',
      filter: 'annotated',
      moreTitleText: '标注',
    }),
    sectionEl({
      title: '最近阅读',
      emptyText: '暂无最近阅读',
      items: data.recentRead?.items || [],
      kind: 'recent',
      filter: 'recent_read',
      moreTitleText: '最近阅读',
    }),
  );
}

async function loadHome() {
  renderHome(null);
  try {
    const data = await fetchHome();
    renderHome(data);
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
  const trash = more.source === 'filter' && more.key === 'trash' && container === moreList;
  for (const item of items) {
    container.append(trash ? trashCardEl(item) : cardEl(item, kind));
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
    items: [],
    total: 0,
    loading: false,
  };
  moreTitle.textContent = title;
  moreList.replaceChildren();
  moreStatus.hidden = false;
  moreStatus.textContent = '加载中…';
  setMoreAction(source === 'filter' && key === 'trash' ? '清空' : '');
  pushView('more');
  await loadMorePage({ reset: true });
}

async function fetchMorePage(offset) {
  const { source, key } = more;
  if (source === 'folder') {
    return listFolderItems(key, { limit: PAGE, offset });
  }
  if (source === 'tag') {
    return listTagItems(key, { limit: PAGE, offset });
  }
  return listItems({ filter: key, limit: PAGE, offset });
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
    fillList(moreList, more.items, more.kind);
    const hasMore = more.items.length < more.total;
    moreStatus.hidden = !hasMore;
    moreStatus.textContent = hasMore ? '上滑加载更多' : '';
    if (!more.items.length) {
      moreStatus.hidden = false;
      moreStatus.textContent = '暂无内容';
    }
  } catch (err) {
    if (await handleAuthError(err)) return;
    moreStatus.hidden = false;
    moreStatus.textContent = err.message || '加载失败';
  } finally {
    more.loading = false;
  }
}

async function runSearch({ reset = false } = {}) {
  const q = searchInput.value.trim();
  if (!q) {
    searchState = emptySearch();
    searchList.replaceChildren();
    searchStatus.hidden = true;
    return;
  }
  if (searchState.loading) return;
  searchState.loading = true;
  searchState.q = q;
  if (reset) {
    searchStatus.hidden = false;
    searchStatus.textContent = '搜索中…';
  }
  try {
    const offset = reset ? 0 : searchState.items.length;
    const data = await searchItems(q, { limit: PAGE, offset });
    const next = Array.isArray(data.items) ? data.items : [];
    searchState.total = Number(data.total ?? next.length);
    searchState.items = reset ? next : searchState.items.concat(next);
    fillList(searchList, searchState.items, 'unread');
    if (!searchState.items.length) {
      searchStatus.hidden = false;
      searchStatus.textContent = '没有匹配的收藏';
    } else {
      const hasMore = searchState.items.length < searchState.total;
      searchStatus.hidden = !hasMore;
      searchStatus.textContent = hasMore ? '上滑加载更多' : '';
    }
  } catch (err) {
    if (await handleAuthError(err)) return;
    searchStatus.hidden = false;
    searchStatus.textContent = err.message || '搜索失败';
  } finally {
    searchState.loading = false;
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

function renderCollection() {
  const s = collectionState;
  collectionBody.replaceChildren();

  collectionBody.append(
    sectionLabel('系统分类', {
      expandable: true,
      expanded: s.systemExpanded,
      onToggle: () => {
        collectionState.systemExpanded = !s.systemExpanded;
        renderCollection();
      },
    }),
  );
  if (s.loading && !s.filters.length) {
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

  if (s.systemExpanded) {
    const unread = s.filters.filter((f) => f.code === 'unread');
    const rest = s.filters.filter((f) => f.code !== 'unread');
    if (unread.length) {
      collectionBody.append(entityGroup(unread.map((f) => filterRow(f))));
    }
    if (rest.length) {
      collectionBody.append(entityGroup(rest.map((f) => filterRow(f))));
    }
  }

  collectionBody.append(
    sectionLabel('收藏夹', {
      expandable: true,
      expanded: s.foldersExpanded,
      onToggle: () => {
        collectionState.foldersExpanded = !s.foldersExpanded;
        renderCollection();
      },
      onAdd: () => openCreateFolder(),
    }),
  );
  if (s.foldersExpanded) {
    collectionBody.append(
      entityGroup(s.folders.map((f) => folderRow(f))),
    );
  }

  collectionBody.append(
    sectionLabel('标签', {
      expandable: true,
      expanded: s.tagsExpanded,
      onToggle: () => {
        collectionState.tagsExpanded = !s.tagsExpanded;
        renderCollection();
      },
      onAdd: () => openCreateTag(),
    }),
  );
  if (s.tagsExpanded) {
    collectionBody.append(
      entityGroup(s.tags.map((t) => tagRow(t))),
    );
  }

  collectionBody.append(
    sectionLabel('其他', {
      expandable: true,
      expanded: s.othersExpanded,
      onToggle: () => {
        collectionState.othersExpanded = !s.othersExpanded;
        renderCollection();
      },
    }),
  );
  if (s.othersExpanded) {
    collectionBody.append(entityGroup(s.others.map((f) => filterRow(f))));
  }
}

function filterRow(filter) {
  return navRow({
    title: filter.name,
    count: filter.countLabel ?? filter.itemCount ?? 0,
    icon: iconForFilter(filter.code),
    onClick: () =>
      openMore({
        source: 'filter',
        key: filter.code,
        title: filter.name,
        kind: kindForFilter(filter.code),
      }),
  });
}

function folderRow(folder) {
  return navRow({
    title: folder.name,
    count: folder.itemCount ?? 0,
    icon: ICON.folder,
    onClick: () =>
      openMore({
        source: 'folder',
        key: folder.id,
        title: folder.name,
        kind: 'unread',
      }),
    onDelete: folder.isSystem
      ? null
      : () => confirmDeleteFolder(folder),
  });
}

function tagRow(tag) {
  return navRow({
    title: tag.name,
    count: tag.itemCount ?? 0,
    icon: tag.isSystem ? ICON.tagSystem : ICON.tagUser,
    onClick: () =>
      openMore({
        source: 'tag',
        key: tag.id,
        title: tag.name,
        kind: 'unread',
      }),
    onDelete: tag.isSystem ? null : () => confirmDeleteTag(tag),
  });
}

async function loadCollection({ quiet = false } = {}) {
  const empty =
    !collectionState.filters.length &&
    !collectionState.folders.length &&
    !collectionState.tags.length;
  if (!quiet || empty) {
    collectionState.loading = true;
    collectionState.error = null;
    renderCollection();
  }
  try {
    const [foldersRes, tagsRes, filtersRes] = await Promise.all([
      listFolders(),
      listTags(),
      fetchSystemFilters(),
    ]);
    collectionState.folders = foldersRes.folders || [];
    collectionState.tags = tagsRes.tags || [];
    collectionState.filters = filtersRes.filters || [];
    collectionState.others = filtersRes.others || [];
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
    if (item?.id) await openDetail(item);
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
  onSubmit,
  afterClose = null,
}) {
  $('name-title').textContent = title;
  $('name-label').textContent = label;
  nameInput.placeholder = placeholder;
  nameInput.value = '';
  nameError.hidden = true;
  nameSave.textContent = submitLabel || '创建';
  nameSave.disabled = false;
  nameSubmit = onSubmit;
  nameAfterClose = afterClose;
  openOverlay('name');
  nameInput.focus();
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

function openCreateFolder() {
  openNameSheet({
    title: '新建收藏夹',
    label: '名称',
    placeholder: '请输入收藏夹名称',
    onSubmit: async (name) => {
      if (!name) throw new Error('请输入收藏夹名称');
      if (name.length > 64) throw new Error('名称最多 64 个字');
      const res = await createFolder(name);
      await loadCollection();
      toast(`已创建「${res.folder?.name || name}」`);
    },
  });
}

function openCreateTag({ afterCreate } = {}) {
  openNameSheet({
    title: '新建标签',
    label: '名称',
    placeholder: '请输入标签名称',
    onSubmit: async (name) => {
      if (!name) throw new Error('请输入标签名称');
      if (name.length > 64) throw new Error('名称最多 64 个字');
      const res = await createTag(name);
      if (!afterCreate) {
        await loadCollection();
        toast(`已创建标签「${res.tag?.name || name}」`);
      }
      return res.tag;
    },
    afterClose: afterCreate,
  });
}

async function confirmDeleteFolder(folder) {
  const ok = await confirmDialog({
    title: '删除收藏夹',
    message: `确定删除「${folder.name}」？夹内条目将移回「未分类」，不会删除条目。`,
    confirmLabel: '删除',
    danger: true,
  });
  if (!ok) return;
  try {
    await deleteFolder(folder.id);
    await loadCollection();
    toast(`已删除「${folder.name}」`);
  } catch (err) {
    if (await handleAuthError(err)) return;
    toast(err.message || '删除失败');
  }
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
    await loadCollection();
    toast(`已删除标签「${tag.name}」`);
  } catch (err) {
    if (await handleAuthError(err)) return;
    toast(err.message || '删除失败');
  }
}

function maskedPhone(phone) {
  const digits = String(phone || '').replace(/\D/g, '');
  if (digits.length >= 7) {
    return `${digits.slice(0, 3)}****${digits.slice(-4)}`;
  }
  return phone || '—';
}

function setRow({ title, meta, danger, chevron, onClick }) {
  const el = document.createElement(onClick ? 'button' : 'div');
  if (onClick) el.type = 'button';
  el.className = `set-row${danger ? ' is-danger' : ''}`;
  const t = document.createElement('span');
  t.className = 'title';
  t.textContent = title;
  el.append(t);
  if (meta != null) {
    const m = document.createElement('span');
    m.className = 'meta';
    m.textContent = meta;
    el.append(m);
  }
  if (chevron) {
    const a = document.createElement('span');
    a.className = 'arrow';
    a.textContent = '›';
    el.append(a);
  }
  if (onClick) el.addEventListener('click', onClick);
  return el;
}

async function openSettings() {
  pushView('settings');
  settingsBody.replaceChildren();
  const session = await getSession();
  const version = chrome.runtime.getManifest().version;

  const accountLabel = document.createElement('div');
  accountLabel.className = 'set-label';
  accountLabel.textContent = '账号';
  const account = document.createElement('div');
  account.className = 'set-group';
  account.append(
    setRow({ title: '手机号', meta: maskedPhone(session?.phone) }),
    setRow({
      title: '退出登录',
      danger: true,
      onClick: logout,
    }),
  );

  const aboutLabel = document.createElement('div');
  aboutLabel.className = 'set-label';
  aboutLabel.textContent = '关于';
  const about = document.createElement('div');
  about.className = 'set-group';
  about.append(
    setRow({
      title: '用户协议',
      chevron: true,
      onClick: () =>
        window.open('https://inkmind.xyz/collection/privacy', '_blank'),
    }),
    setRow({
      title: '隐私政策',
      chevron: true,
      onClick: () =>
        window.open('https://inkmind.xyz/collection/privacy', '_blank'),
    }),
    setRow({ title: '关于 Conflux', meta: `v${version}` }),
  );

  const hint = document.createElement('p');
  hint.className = 'list-msg';
  hint.textContent = '阅读、标注和视频仍在手机 App 里完成。';

  settingsBody.append(accountLabel, account, aboutLabel, about, hint);
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
  meta.textContent = [platformLabel(item.platform), formatDateTime(item.createdAt)]
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

  detailBody.append(title, meta, chip, url);

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

async function openFolderPicker() {
  hideDetailMenu();
  const item = detailState.item;
  if (!item) return;
  $('pick-title').textContent = '移动到收藏夹';
  $('pick-save').hidden = true;
  pickSave = null;
  openOverlay('pick');
  renderPickList([]);
  try {
    const res = await listFolders();
    const folders = res.folders || [];
    renderPickList(
      folders.map((folder) => {
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'pick-row';
        btn.innerHTML = '<span class="name"></span><span class="check"></span>';
        btn.querySelector('.name').textContent = folder.name;
        if (folder.id === item.folderId) {
          btn.querySelector('.check').textContent = '✓';
        }
        btn.addEventListener('click', async () => {
          if (folder.id === item.folderId) {
            closeOverlay({ cancel: false });
            return;
          }
          try {
            overlayBusy = true;
            const patched = await patchItem(item.id, { folderId: folder.id });
            detailState.item = patched.item || { ...item, folderId: folder.id };
            overlayBusy = false;
            closeOverlay({ cancel: false });
            toast(`已移入「${folder.name}」`);
          } catch (err) {
            overlayBusy = false;
            if (await handleAuthError(err)) {
              closeOverlay({ cancel: false });
              return;
            }
            toast(err.message || '移动失败');
          }
        });
        return btn;
      }),
    );
  } catch (err) {
    if (await handleAuthError(err)) {
      closeOverlay({ cancel: false });
      return;
    }
    toast(err.message || '加载收藏夹失败');
    closeOverlay({ cancel: false });
  }
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
    title: '彻底删除？',
    message: '删除后不可恢复。',
    confirmLabel: '删除',
    danger: true,
  });
  if (!ok) return;
  try {
    await purgeItem(item.id);
    toast('已彻底删除');
    popView();
  } catch (err) {
    if (await handleAuthError(err)) return;
    toast(err.message || '删除失败');
  }
}

async function restoreTrashItem(item) {
  try {
    await restoreItem(item.id);
    toast('已恢复');
    await loadMorePage({ reset: true });
  } catch (err) {
    if (await handleAuthError(err)) return;
    toast(err.message || '恢复失败');
  }
}

async function purgeTrashItem(item) {
  const ok = await confirmDialog({
    title: '彻底删除？',
    message: '删除后不可恢复。',
    confirmLabel: '删除',
    danger: true,
  });
  if (!ok) return;
  try {
    await purgeItem(item.id);
    toast('已彻底删除');
    await loadMorePage({ reset: true });
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

saveBtn.addEventListener('click', () => openAddLink());
$('search-btn').addEventListener('click', () => {
  pushView('search');
  searchInput.value = '';
  searchList.replaceChildren();
  searchStatus.hidden = true;
  searchInput.focus();
});
$('settings-btn').addEventListener('click', openSettings);
$('search-back').addEventListener('click', popView);
$('more-back').addEventListener('click', popView);
$('detail-back').addEventListener('click', popView);
$('settings-back').addEventListener('click', popView);
$('detail-more').addEventListener('click', (e) => {
  e.stopPropagation();
  toggleDetailMenu();
});
$('detail-copy').addEventListener('click', copyDetailLink);
$('detail-folder').addEventListener('click', openFolderPicker);
$('detail-tags').addEventListener('click', openTagPicker);
$('detail-delete').addEventListener('click', deleteCurrentItem);
$('detail-menu').addEventListener('click', (e) => e.stopPropagation());
document.addEventListener('click', () => hideDetailMenu());

moreAction.addEventListener('click', async () => {
  if (more.source !== 'filter' || more.key !== 'trash') return;
  const ok = await confirmDialog({
    title: '清空回收站',
    message: '将彻底删除回收站中的全部条目，无法恢复。',
    confirmLabel: '清空',
    danger: true,
  });
  if (!ok) return;
  try {
    await emptyTrash();
    toast('回收站已清空');
    await loadMorePage({ reset: true });
  } catch (err) {
    if (await handleAuthError(err)) return;
    toast(err.message || '清空失败');
  }
});

searchInput.addEventListener('input', () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => runSearch({ reset: true }), 280);
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
