import { API_BASE } from './config.js';

const KEYS = {
  access: 'accessToken',
  refresh: 'refreshToken',
  userId: 'userId',
  phone: 'phone',
  nickname: 'nickname',
};

export async function getSession() {
  const data = await chrome.storage.local.get(Object.values(KEYS));
  if (!data[KEYS.access] || !data[KEYS.refresh] || !data[KEYS.phone]) {
    return null;
  }
  return {
    accessToken: data[KEYS.access],
    refreshToken: data[KEYS.refresh],
    userId: data[KEYS.userId],
    phone: data[KEYS.phone],
    nickname: data[KEYS.nickname] || '',
  };
}

export async function saveSession(session) {
  await chrome.storage.local.set({
    [KEYS.access]: session.accessToken,
    [KEYS.refresh]: session.refreshToken,
    [KEYS.userId]: session.userId,
    [KEYS.phone]: session.phone,
    [KEYS.nickname]: session.nickname || '',
  });
}

export async function clearSession() {
  await chrome.storage.local.remove(Object.values(KEYS));
}

function tzOffsetMinutes() {
  return -new Date().getTimezoneOffset();
}

async function request(method, path, { body, token, retry = true } = {}) {
  const headers = { Accept: 'application/json' };
  if (body) headers['Content-Type'] = 'application/json';
  if (token) headers.Authorization = `Bearer ${token}`;

  const res = await fetch(`${API_BASE}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });

  let json = {};
  try {
    json = await res.json();
  } catch {
    json = {};
  }

  if (res.status === 401 && retry && token) {
    const next = await refreshAccessToken();
    if (next) {
      return request(method, path, { body, token: next, retry: false });
    }
    await clearSession();
    throw new Error(json.message || '登录已过期，请重新登录');
  }

  if (!res.ok) {
    throw new Error(json.message || '请求失败');
  }
  return json;
}

async function refreshAccessToken() {
  const session = await getSession();
  if (!session?.refreshToken) return null;
  try {
    const json = await request('POST', '/api/auth/refresh', {
      body: { refreshToken: session.refreshToken },
      retry: false,
    });
    const next = {
      ...session,
      accessToken: json.accessToken,
      refreshToken: json.refreshToken || session.refreshToken,
    };
    await saveSession(next);
    return next.accessToken;
  } catch {
    return null;
  }
}

async function authRequest(method, path, { body } = {}) {
  const session = await getSession();
  if (!session) {
    throw new Error('请先登录');
  }
  return request(method, path, { body, token: session.accessToken });
}

export function sendCode(phone) {
  return request('POST', '/api/auth/sms/send', { body: { phone } });
}

export async function login(phone, code) {
  const json = await request('POST', '/api/auth/sms/login', {
    body: { phone, code },
  });
  const user = json.user || {};
  const session = {
    accessToken: json.accessToken,
    refreshToken: json.refreshToken,
    userId: user.id,
    phone: user.phone,
    nickname: user.nickname || '',
  };
  await saveSession(session);
  return session;
}

export async function saveUrl(url) {
  return authRequest('POST', '/api/items', { body: { url } });
}

export async function listItems({
  filter = 'all',
  limit = 30,
  offset = 0,
} = {}) {
  const qs = new URLSearchParams({
    filter,
    limit: String(limit),
    offset: String(offset),
    tzOffsetMinutes: String(tzOffsetMinutes()),
  });
  return authRequest('GET', `/api/items?${qs}`);
}

export async function fetchHome() {
  return authRequest(
    'GET',
    `/api/home?tzOffsetMinutes=${tzOffsetMinutes()}`,
  );
}

export async function searchItems(q, { limit = 30, offset = 0 } = {}) {
  const qs = new URLSearchParams({
    q,
    limit: String(limit),
    offset: String(offset),
  });
  return authRequest('GET', `/api/items/search?${qs}`);
}

export async function fetchSystemFilters() {
  return authRequest(
    'GET',
    `/api/system-filters?tzOffsetMinutes=${tzOffsetMinutes()}`,
  );
}

export function listTags() {
  return authRequest('GET', '/api/tags');
}

export function createTag(name) {
  return authRequest('POST', '/api/tags', { body: { name } });
}

export function deleteTag(id) {
  return authRequest('DELETE', `/api/tags/${id}`);
}

export function listTagItems(id, { limit = 30, offset = 0 } = {}) {
  const qs = new URLSearchParams({
    limit: String(limit),
    offset: String(offset),
  });
  return authRequest('GET', `/api/tags/${id}/items?${qs}`);
}

export function fetchItem(id) {
  return authRequest('GET', `/api/items/${id}`);
}

export function reparseItem(id) {
  return authRequest('POST', `/api/items/${id}/reparse`);
}

export function patchItem(id, body) {
  return authRequest('PATCH', `/api/items/${id}`, { body });
}

export function listItemTags(id) {
  return authRequest('GET', `/api/items/${id}/tags`);
}

export function setItemTags(id, tagIds) {
  return authRequest('PUT', `/api/items/${id}/tags`, { body: { tagIds } });
}

export function restoreItem(id) {
  return authRequest('POST', `/api/items/${id}/restore`);
}

export function purgeItem(id) {
  return authRequest('DELETE', `/api/items/${id}/permanent`);
}

export function emptyTrash() {
  return authRequest('DELETE', '/api/items/trash');
}

export function canSaveUrl(url) {
  if (!url) return false;
  try {
    const u = new URL(url);
    return u.protocol === 'http:' || u.protocol === 'https:';
  } catch {
    return false;
  }
}
