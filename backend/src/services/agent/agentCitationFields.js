const mediaProxy = require('../mediaProxy');
const itemMediaOss = require('../itemMediaOss');
const {
  normalizeBilibiliCanonical,
  normalizeXiaohongshuCanonical,
  normalizeDoubanCanonical,
} = require('../../utils/url');

/** 与 mapItem 一致：封面走代理 / OSS 签名后再给 App */
function outgoingCoverUrl(raw) {
  const s = String(raw || '').trim();
  if (!s) return null;
  return (
    itemMediaOss.rewriteOutgoingUrl(mediaProxy.toProxiedMediaUrl(s)) || null
  );
}

/**
 * 防盗链 Referer 用的源站页：优先规范化 canonical。
 * @param {{ platform?: string|null, canonicalUrl?: string|null, canonical_url?: string|null, url?: string|null }} source
 */
function pageUrlFromSource(source) {
  if (!source || typeof source !== 'object') return null;
  const platform = String(source.platform || '').toLowerCase();
  const candidates = [
    source.canonicalUrl,
    source.canonical_url,
    source.url,
    source.pageUrl,
  ]
    .map((u) => String(u || '').trim())
    .filter(Boolean);

  if (platform === 'bilibili') {
    for (const c of candidates) {
      const n = normalizeBilibiliCanonical(c);
      if (n) return n;
    }
  }
  if (platform === 'xiaohongshu') {
    for (const c of candidates) {
      const n = normalizeXiaohongshuCanonical(c);
      if (n) return n;
    }
  }
  if (platform === 'douban') {
    for (const c of candidates) {
      const n = normalizeDoubanCanonical(c);
      if (n) return n;
    }
  }

  return candidates[0] || null;
}

/**
 * 出处卡媒体字段（封面 + pageUrl）。
 * 接受 mapItem 结果或 DB row。
 */
function citationMediaFields(source) {
  const coverRaw =
    source?.coverImageUrl != null
      ? source.coverImageUrl
      : source?.cover_image_url;
  return {
    coverImageUrl: outgoingCoverUrl(coverRaw),
    pageUrl: pageUrlFromSource(source),
  };
}

module.exports = {
  outgoingCoverUrl,
  pageUrlFromSource,
  citationMediaFields,
};
