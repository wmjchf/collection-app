const cheerio = require('cheerio');
const sm3 = require('sm3');
const { htmlToRichText, absolutize } = require('../htmlText');
const { xinhuaxmtDocId } = require('../../../utils/url');

/**
 * 新华社客户端分享页 h.xinhuaxmt.com：HTML 是 SPA 空壳，正文走 H5 签名 API。
 * @type {import('./registry').PlatformAdapter}
 */

const MOBILE_UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) ' +
  'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 ' +
  'Mobile/15E148 Safari/604.1';

const API_BASE = 'https://h.xinhuaxmt.com/1017';
const IMG_BASE = 'https://img-xhpfm.xinhuaxmt.com';
const H5_KEY = sm3('H5');

function pickDocId(url) {
  return xinhuaxmtDocId(url);
}

function httpsUrl(raw, baseUrl) {
  return absolutize(baseUrl || IMG_BASE, raw);
}

function mdUrl(raw) {
  return String(raw || '').replace(/[)\s]/g, (ch) => encodeURIComponent(ch));
}

function mdAttr(raw) {
  return String(raw || '').replace(/[\]\s]/g, (ch) => encodeURIComponent(ch));
}

function videoMarkdown(playUrl, posterUrl) {
  return `\n\n!v[${mdAttr(posterUrl || '')}](${mdUrl(playUrl)})\n\n`;
}

function signGetRequest(queryParams) {
  const ts = Date.now();
  const sorted = Object.keys(queryParams)
    .filter((k) => queryParams[k] !== undefined && queryParams[k] !== null)
    .sort()
    .map((k) => `${k}=${queryParams[k]}`)
    .join('&');
  const payload = `Key=${H5_KEY}&Timestamp=${ts}&Token=&Request=${sorted || ''}`;
  return {
    ts,
    sig: sm3(payload),
    query: sorted,
  };
}

function parseApiData(raw) {
  if (!raw || typeof raw !== 'string') return null;
  const trimmed = raw.trim();
  const m = trimmed.match(/=\s*(\{[\s\S]*\})\s*;?\s*$/);
  const jsonText = m ? m[1] : trimmed;
  try {
    return JSON.parse(jsonText);
  } catch {
    return null;
  }
}

async function fetchNewsDetail(docid, pageUrl) {
  const referer =
    pageUrl || `https://h.xinhuaxmt.com/vh512/share/${docid}?docid=${docid}`;
  const { ts, sig } = signGetRequest({ sign: '' });
  const uri = `${API_BASE}/n/newsapi/h5/news-detail/${encodeURIComponent(docid)}?sign=`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 12000);
  try {
    const res = await fetch(uri, {
      signal: controller.signal,
      headers: {
        'User-Agent': MOBILE_UA,
        Accept: 'application/json',
        Referer: referer,
        Timestamp: String(ts),
        Signature: sig,
        'Device-Access-Id': '',
      },
    });
    if (!res.ok) return null;
    const json = await res.json();
    if (json?.code !== '0' || !json?.data) return null;
    return parseApiData(json.data);
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

function takeHtmlVideos(fragment, baseUrl) {
  const $ = cheerio.load(`<div id="__root">${fragment || ''}</div>`);
  const videos = [];
  $('#__root video').each((_, el) => {
    const $el = $(el);
    const i = videos.length;
    const play = httpsUrl($el.attr('src'), baseUrl);
    const poster = httpsUrl($el.attr('poster'), baseUrl);
    if (play) videos.push({ play, poster });
    $el.replaceWith(`<p>%%XHSVIDEO_${i}%%</p>`);
  });
  return { html: $('#__root').html() || '', videos };
}

/** 去掉 link-image 包裹、空段。 */
function scrubChrome(fragment) {
  const $ = cheerio.load(`<div id="__root">${fragment || ''}</div>`);
  $('#__root a.link-image').each((_, el) => {
    const $el = $(el);
    const img = $el.find('img').first();
    if (img.length) $el.replaceWith(img);
    else $el.remove();
  });
  $('#__root p').each((_, el) => {
    const $el = $(el);
    if ($el.find('img, video').length) return;
    const t = $el.text().replace(/\s+/g, ' ').trim();
    if (!t) $el.remove();
  });
  return $('#__root').html() || '';
}

function firstContentImage(html, baseUrl) {
  if (!html) return null;
  const $ = cheerio.load(`<div>${html}</div>`);
  const src =
    $('img').first().attr('data-src') ||
    $('img').first().attr('src') ||
    null;
  return httpsUrl(src, baseUrl);
}

function mapParsed(detail, url) {
  const pageBase = url || `https://h.xinhuaxmt.com/vh512/share/${detail?.id || ''}`;
  const title = String(detail?.topic || detail?.shortTopic || '').trim();
  const summary = String(detail?.summary || '').trim() || null;
  const author = String(detail?.authors || '').trim() || null;
  const poster =
    httpsUrl(detail?.shareImage, IMG_BASE) ||
    httpsUrl(Array.isArray(detail?.imglist) ? detail.imglist[0] : null, IMG_BASE) ||
    null;

  const { html: scrubbed, videos: htmlVideos } = takeHtmlVideos(
    scrubChrome(String(detail?.content || '')),
    IMG_BASE,
  );
  let body = htmlToRichText(scrubbed, { baseUrl: IMG_BASE }) || '';

  for (let i = 0; i < htmlVideos.length; i += 1) {
    const v = htmlVideos[i];
    const replacement = v.play
      ? videoMarkdown(v.play, v.poster || poster || '')
      : '';
    body = body.split(`%%XHSVIDEO_${i}%%`).join(replacement);
  }

  const playUrl = httpsUrl(detail?.videourl, IMG_BASE);
  if (playUrl && !body.includes(playUrl)) {
    body = videoMarkdown(playUrl, poster) + body;
  }

  const cover = poster || firstContentImage(String(detail?.content || ''), IMG_BASE);

  return {
    ok: true,
    title: title || null,
    summary,
    coverImageUrl: cover,
    author,
    imageUrls: [],
    videoUrl: playUrl || null,
    content: body.trim() || summary,
    errorMessage: null,
  };
}

module.exports = {
  id: 'xinhuaxmt',
  fetchMode: 'server',
  contentImageSelectors: ['.article img', '.news-content img', 'img'],
  detectFromHtml(html) {
    return typeof html === 'string' && /xinhuaxmt\.com/i.test(html);
  },
  async fetchParsed(url) {
    const docid = pickDocId(url);
    if (!docid) {
      return {
        ok: false,
        title: null,
        summary: null,
        coverImageUrl: null,
        author: null,
        imageUrls: [],
        videoUrl: null,
        content: null,
        errorMessage: '无法识别新华社文章 ID',
      };
    }
    const detail = await fetchNewsDetail(docid, url);
    if (!detail) {
      return {
        ok: false,
        title: null,
        summary: null,
        coverImageUrl: null,
        author: null,
        imageUrls: [],
        videoUrl: null,
        content: null,
        errorMessage: '新华社接口抓取失败',
      };
    }
    return mapParsed(detail, url);
  },
};
