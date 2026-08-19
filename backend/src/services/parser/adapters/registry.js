/**
 * 平台解析适配器
 *
 * 新站：新增 adapters/<name>.js 并在 registry 注册即可。
 *
 * @typedef {'server' | 'client'} FetchMode
 *   server — 云端抓 HTML 再抽
 *   client — 云端常被拦，标 NEED_CLIENT_FETCH，等本机抓 HTML 回传
 *
 * @typedef {{
 *   id: string,
 *   fetchMode?: FetchMode,
 *   detectFromHtml?: (html: string) => boolean,
 *   contentImageSelectors?: string[],
 *   extractMeta?: (html: string, ctx: { baseUrl?: string, $: any }) => ({
 *     title?: string|null,
 *     summary?: string|null,
 *     coverImageUrl?: string|null,
 *     author?: string|null,
 *   } | null),
 *   extractContent?: (html: string, ctx?: object) => ({
 *     content?: string|null,
 *     summary?: string|null,
 *     imageUrls?: string[],
 *     videoUrl?: string|null,
 *   } | null) | Promise<{
 *     content?: string|null,
 *     summary?: string|null,
 *     imageUrls?: string[],
 *     videoUrl?: string|null,
 *   } | null),
 * }} PlatformAdapter
 */

const defaultAdapter = require('./default');
const weixinAdapter = require('./weixin');
const channelsAdapter = require('./channels');
const jikeAdapter = require('./jike');
const xiaohongshuAdapter = require('./xiaohongshu');
const weiboAdapter = require('./weibo');
const douyinAdapter = require('./douyin');
const bilibiliAdapter = require('./bilibili');
const kuaishouAdapter = require('./kuaishou');
const kr36Adapter = require('./kr36');
const toutiaoAdapter = require('./toutiao');
const peopleAdapter = require('./people');
const qqnewsAdapter = require('./qqnews');
const sinaAdapter = require('./sina');
const thepaperAdapter = require('./thepaper');
const infzmAdapter = require('./infzm');

/** @type {PlatformAdapter[]} */
const ADAPTERS = [
  channelsAdapter,
  weixinAdapter,
  douyinAdapter,
  kuaishouAdapter,
  bilibiliAdapter,
  jikeAdapter,
  xiaohongshuAdapter,
  weiboAdapter,
  kr36Adapter,
  toutiaoAdapter,
  peopleAdapter,
  qqnewsAdapter,
  sinaAdapter,
  thepaperAdapter,
  infzmAdapter,
  defaultAdapter,
];

const BY_ID = new Map(ADAPTERS.map((a) => [a.id, a]));

/**
 * @param {string|null|undefined} platform
 * @param {string} [html]
 * @returns {PlatformAdapter}
 */
function getAdapter(platform, html) {
  const id = (platform || '').toLowerCase();
  if (id && BY_ID.has(id) && id !== 'web') {
    return BY_ID.get(id);
  }
  if (html) {
    for (const a of ADAPTERS) {
      if (a.id === 'web') continue;
      if (typeof a.detectFromHtml === 'function' && a.detectFromHtml(html)) {
        return a;
      }
    }
  }
  return defaultAdapter;
}

/** 是否应走本机抓页（不等云端正文解析） */
function prefersClientFetch(platform) {
  const a = getAdapter(platform);
  return (a.fetchMode || 'server') === 'client';
}

/** fetchMode=client 的平台 id 列表（供 SQL / 列表筛选） */
function listClientFetchPlatformIds() {
  return ADAPTERS.filter(
    (a) => a.id !== 'web' && (a.fetchMode || 'server') === 'client',
  ).map((a) => a.id);
}

function listAdapters() {
  return ADAPTERS.filter((a) => a.id !== 'web').map((a) => ({
    id: a.id,
    fetchMode: a.fetchMode || 'server',
  }));
}

module.exports = {
  getAdapter,
  prefersClientFetch,
  listClientFetchPlatformIds,
  listAdapters,
  defaultAdapter,
};
