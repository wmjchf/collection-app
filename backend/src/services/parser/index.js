const { fetchHtml } = require('./fetchHtml');
const { extractMeta } = require('./extractMeta');
const { extractContent } = require('./extractContent');
const {
  detectPlatform,
  placeholderTitle,
  resolveFetchUrl,
} = require('../../utils/url');

function fetchTargetUrl(url) {
  return resolveFetchUrl(url) || url;
}

/**
 * 阶段 1：短超时抓取 + 元信息
 */
async function fetchQuickMeta(url) {
  const platform = detectPlatform(url);
  const target = fetchTargetUrl(url);
  const { html, finalUrl, status, ok } = await fetchHtml(target, {
    timeoutMs: 8000,
  });
  const pageUrl = finalUrl || target;
  const meta = extractMeta(html, { platform, baseUrl: pageUrl });

  let title = meta.title;
  if (!title || meta.blocked) {
    title = title || placeholderTitle(pageUrl);
  }

  return {
    platform,
    finalUrl: pageUrl,
    httpStatus: status,
    fetchOk: ok,
    title,
    summary: meta.summary,
    coverImageUrl: meta.coverImageUrl,
    author: meta.author,
    blocked: meta.blocked,
    // 复用同一份 HTML，避免阶段 2 再抓一次（失败/风控时阶段 2 可重抓）
    html,
  };
}

/**
 * 阶段 2：从 HTML 抽正文；必要时重新抓取
 */
async function parseFullContent(url, { platform, existingSummary, html } = {}) {
  const resolvedPlatform = platform || detectPlatform(url);
  const target = fetchTargetUrl(url);
  let sourceHtml = html;
  let blocked = false;
  let pageUrl = target;

  // 缓存 HTML 若是验证码壳页，丢弃并改走可读页重抓
  if (sourceHtml) {
    const pre = extractMeta(sourceHtml, {
      platform: resolvedPlatform,
      baseUrl: url,
    });
    if (pre.blocked) sourceHtml = null;
  }

  if (!sourceHtml) {
    const fetched = await fetchHtml(target, { timeoutMs: 15000 });
    sourceHtml = fetched.html;
    pageUrl = fetched.finalUrl || target;
  }

  let meta = extractMeta(sourceHtml, {
    platform: resolvedPlatform,
    baseUrl: pageUrl,
  });
  blocked = meta.blocked;

  if (blocked) {
    // 风控页：改走可读页再试 / 或再抓一次
    const retryUrl = fetchTargetUrl(url);
    const retry = await fetchHtml(retryUrl, { timeoutMs: 15000 });
    sourceHtml = retry.html;
    pageUrl = retry.finalUrl || retryUrl;
    meta = extractMeta(sourceHtml, {
      platform: resolvedPlatform,
      baseUrl: pageUrl,
    });
    blocked = meta.blocked;
    if (blocked) {
      return {
        ok: false,
        blocked: true,
        title: meta.title,
        summary: meta.summary || existingSummary || null,
        coverImageUrl: meta.coverImageUrl,
        content: null,
        errorMessage: '页面需验证，暂时无法解析正文',
      };
    }
  }

  const { content, summary } = extractContent(sourceHtml, {
    platform: resolvedPlatform,
    existingSummary: existingSummary || meta.summary,
  });

  if (!content) {
    return {
      ok: false,
      blocked: false,
      title: meta.title,
      summary: summary || meta.summary || existingSummary || null,
      coverImageUrl: meta.coverImageUrl,
      content: null,
      errorMessage: '未能提取到可读正文',
    };
  }

  return {
    ok: true,
    blocked: false,
    title: meta.title,
    summary,
    coverImageUrl: meta.coverImageUrl,
    content,
    errorMessage: null,
  };
}

module.exports = {
  fetchQuickMeta,
  parseFullContent,
};
