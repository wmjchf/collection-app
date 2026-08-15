/**
 * 抖音：短链解析 aweme id → 移动端分享页 HTML → _ROUTER_DATA 抽文案/封面/视频。
 * 云主机常遇字节 WAF（waf_js），此时应标 blocked 走本机抓页。
 */

const MOBILE_UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) ' +
  'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 ' +
  'Mobile/15E148 Safari/604.1';

function preferHttps(url) {
  if (!url) return null;
  let u = String(url).trim();
  if (u.startsWith('//')) u = `https:${u}`;
  if (u.startsWith('http://')) u = `https://${u.slice(7)}`;
  if (!u.startsWith('https://')) return null;
  // 去水印常见技巧
  u = u.replace(/\/playwm\//g, '/play/');
  return u;
}

function extractAwemeId(rawUrl) {
  try {
    const uri = new URL(String(rawUrl || '').trim());
    const path = uri.pathname;
    let m =
      path.match(/\/video\/(\d{5,})/i) ||
      path.match(/\/share\/video\/(\d{5,})/i) ||
      path.match(/\/note\/(\d{5,})/i);
    if (m) return m[1];
    const q =
      uri.searchParams.get('modal_id') ||
      uri.searchParams.get('aweme_id') ||
      uri.searchParams.get('item_ids');
    if (q && /^\d{5,}$/.test(q)) return q;
  } catch {
    // ignore
  }
  return null;
}

function isWafChallenge(html) {
  if (!html || typeof html !== 'string') return true;
  const head = html.slice(0, 4000);
  if (/waf_js|waf-jschallenge|x-tt-system-error|___vm_challenge/i.test(head)) {
    return true;
  }
  if (html.length < 8000 && /slardar\/fe\/sdk-web|byted-static\.com\/obj\/waf/i.test(head)) {
    return true;
  }
  return false;
}

async function resolveShareUrl(rawUrl) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 12000);
  try {
    const res = await fetch(rawUrl, {
      redirect: 'manual',
      signal: controller.signal,
      headers: {
        'User-Agent': MOBILE_UA,
        Accept: 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
      },
    });
    const loc = res.headers.get('location');
    if (loc && (res.status === 301 || res.status === 302 || res.status === 303 || res.status === 307 || res.status === 308)) {
      return new URL(loc, rawUrl).toString();
    }
    return res.url || rawUrl;
  } finally {
    clearTimeout(timer);
  }
}

async function fetchText(url) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 15000);
  try {
    const res = await fetch(url, {
      redirect: 'follow',
      signal: controller.signal,
      headers: {
        'User-Agent': MOBILE_UA,
        Accept: 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        Referer: 'https://www.douyin.com/',
      },
    });
    const html = await res.text();
    return { ok: res.ok, status: res.status, finalUrl: res.url || url, html };
  } finally {
    clearTimeout(timer);
  }
}

function parseRouterData(html) {
  if (!html) return null;
  // 旧版：<script id="_ROUTER_DATA" type="application/json">...</script>
  let m =
    html.match(
      /<script[^>]*id="_ROUTER_DATA"[^>]*type="application\/json"[^>]*>([\s\S]*?)<\/script>/i,
    ) ||
    html.match(/<script[^>]*id="_ROUTER_DATA"[^>]*>([\s\S]*?)<\/script>/i);
  // 新版分享页：window._ROUTER_DATA = {...}
  if (!m) {
    m = html.match(
      /window\._ROUTER_DATA\s*=\s*(\{[\s\S]*?\})\s*;?\s*<\/script>/i,
    );
  }
  if (!m) return null;
  try {
    return JSON.parse(m[1].trim());
  } catch {
    return null;
  }
}

function firstUrlList(obj) {
  if (!obj) return null;
  const list = obj.url_list || obj.urlList || obj.uri_list;
  if (Array.isArray(list)) {
    for (const u of list) {
      const https = preferHttps(u);
      if (https) return https;
    }
  }
  return preferHttps(obj.url || obj.uri || null);
}

function pickFromAweme(aweme) {
  if (!aweme || typeof aweme !== 'object') return null;
  const desc = String(aweme.desc || aweme.title || '').trim();
  const author =
    aweme.author?.nickname ||
    aweme.authorInfo?.nickname ||
    aweme.author?.nick_name ||
    null;
  const video = aweme.video || {};
  let videoUrl =
    firstUrlList(video.play_addr) ||
    firstUrlList(video.play_addr_h264) ||
    firstUrlList(video.playAddr) ||
    firstUrlList(video.download_addr) ||
    null;
  if (!videoUrl && Array.isArray(video.bit_rate)) {
    // 取最高档
    const sorted = [...video.bit_rate].sort(
      (a, b) => (Number(b.bit_rate) || 0) - (Number(a.bit_rate) || 0),
    );
    for (const br of sorted) {
      videoUrl = firstUrlList(br.play_addr || br.playAddr);
      if (videoUrl) break;
    }
  }

  const imageUrls = [];
  const push = (u) => {
    const https = preferHttps(u);
    if (https && !imageUrls.includes(https)) imageUrls.push(https);
  };
  push(firstUrlList(video.cover));
  push(firstUrlList(video.origin_cover));
  push(firstUrlList(video.dynamic_cover));
  if (Array.isArray(aweme.images)) {
    for (const img of aweme.images) {
      push(firstUrlList(img.url_list ? img : img));
      push(firstUrlList(img.download_url_list ? { url_list: img.download_url_list } : null));
    }
  }

  const title =
    (desc.split(/\n+/).map((s) => s.trim()).find(Boolean) || '').slice(0, 40) ||
    (author ? `${author}的抖音` : null);

  const parts = [];
  if (author) parts.push(`作者：${author}`);
  if (desc) parts.push(desc);
  const content = parts.join('\n\n').trim() || null;

  if (!content && !imageUrls.length && !videoUrl) return null;

  return {
    title,
    content: content || title || (videoUrl ? '（抖音视频）' : '（抖音图片）'),
    summary: (desc || title || '').replace(/\s+/g, ' ').trim().slice(0, 180) || null,
    coverImageUrl: imageUrls[0] || null,
    author,
    imageUrls,
    videoUrl,
  };
}

function findAwemeInTree(node, depth = 0) {
  if (!node || typeof node !== 'object' || depth > 12) return null;
  if (node.video && (node.desc != null || node.author) && (node.aweme_id || node.awemeId || node.video)) {
    const picked = pickFromAweme(node);
    if (picked?.videoUrl || picked?.content) return picked;
  }
  if (Array.isArray(node.item_list) && node.item_list[0]) {
    const picked = pickFromAweme(node.item_list[0]);
    if (picked) return picked;
  }
  if (node.aweme_detail) {
    const picked = pickFromAweme(node.aweme_detail);
    if (picked) return picked;
  }
  if (node.awemeDetail) {
    const picked = pickFromAweme(node.awemeDetail);
    if (picked) return picked;
  }
  if (Array.isArray(node)) {
    for (const x of node) {
      const found = findAwemeInTree(x, depth + 1);
      if (found) return found;
    }
    return null;
  }
  for (const v of Object.values(node)) {
    if (v && typeof v === 'object') {
      const found = findAwemeInTree(v, depth + 1);
      if (found) return found;
    }
  }
  return null;
}

/** 从分享页 / 本机回传 HTML 抽取 */
function extractDouyinFromHtml(html) {
  if (!html || typeof html !== 'string') return null;
  if (isWafChallenge(html)) return null;

  // App WebView 注入的抽取块
  const injected = html.match(
    /<script[^>]*id=["']SC_DOUYIN_EXTRACT["'][^>]*>([\s\S]*?)<\/script>/i,
  );
  if (injected) {
    try {
      const data = JSON.parse(injected[1].trim());
      const videoUrl = preferHttps(data.videoUrl);
      const cover = preferHttps(data.cover);
      const desc = data.desc ? String(data.desc).trim() : '';
      const author = data.author ? String(data.author).trim() : null;
      const title =
        (data.title ? String(data.title).trim().slice(0, 80) : null) ||
        (desc.split(/\n+/).map((s) => s.trim()).find(Boolean) || '').slice(0, 40) ||
        null;
      if (videoUrl || cover || title || desc) {
        const parts = [];
        if (author) parts.push(`作者：${author}`);
        if (desc) parts.push(desc);
        else if (title) parts.push(title);
        return {
          title: title || (author ? `${author}的抖音` : null),
          content:
            parts.join('\n\n').trim() ||
            title ||
            (videoUrl ? '（抖音视频）' : null),
          summary: (desc || title || '').replace(/\s+/g, ' ').trim().slice(0, 180) || null,
          coverImageUrl: cover,
          author,
          imageUrls: cover ? [cover] : [],
          videoUrl,
        };
      }
    } catch {
      // fall through
    }
  }

  const router = parseRouterData(html);
  if (router) {
    const fromRouter = findAwemeInTree(router.loaderData || router);
    if (fromRouter) return fromRouter;
  }

  // 兜底：页面里 video src / og
  const videoTag =
    (html.match(/<video[^>]+(?:src|data-src)=["']([^"']+)["']/i) || [])[1] ||
    null;
  const ogTitle =
    (html.match(/property=["']og:title["']\s+content=["']([^"']+)["']/i) ||
      html.match(/content=["']([^"']+)["']\s+property=["']og:title["']/i) ||
      [])[1] || null;
  const ogImage =
    (html.match(/property=["']og:image["']\s+content=["']([^"']+)["']/i) ||
      html.match(/content=["']([^"']+)["']\s+property=["']og:image["']/i) ||
      [])[1] || null;
  const ogVideo =
    (html.match(/property=["']og:video(?::url)?["']\s+content=["']([^"']+)["']/i) ||
      [])[1] || null;

  const videoUrl = preferHttps(videoTag || ogVideo);
  const cover = preferHttps(ogImage);
  const title = ogTitle ? String(ogTitle).trim().slice(0, 80) : null;
  if (!videoUrl && !cover && !title) return null;

  return {
    title,
    content: title || (videoUrl ? '（抖音视频）' : null),
    summary: title,
    coverImageUrl: cover,
    author: null,
    imageUrls: cover ? [cover] : [],
    videoUrl,
  };
}

/**
 * @returns {Promise<{
 *   ok: boolean,
 *   blocked?: boolean,
 *   title: string|null,
 *   content: string|null,
 *   summary: string|null,
 *   coverImageUrl: string|null,
 *   author: string|null,
 *   imageUrls: string[],
 *   videoUrl: string|null,
 *   errorMessage: string|null,
 * }>}
 */
async function fetchDouyin(rawUrl) {
  try {
    let shareUrl = await resolveShareUrl(rawUrl);
    let awemeId = extractAwemeId(shareUrl) || extractAwemeId(rawUrl);

    // 无追踪参数的分享页兜底
    const candidates = [];
    if (shareUrl) candidates.push(shareUrl);
    if (awemeId) {
      candidates.push(`https://www.iesdouyin.com/share/video/${awemeId}/`);
      candidates.push(`https://m.douyin.com/share/video/${awemeId}`);
    }

    let lastHtml = '';
    let sawWaf = false;
    for (const url of candidates) {
      const { html, finalUrl } = await fetchText(url);
      lastHtml = html || '';
      if (isWafChallenge(lastHtml)) {
        sawWaf = true;
        continue;
      }
      if (!awemeId) awemeId = extractAwemeId(finalUrl);
      const note = extractDouyinFromHtml(lastHtml);
      if (note) {
        return {
          ok: true,
          blocked: false,
          title: note.title,
          content: note.content,
          summary: note.summary,
          coverImageUrl: note.coverImageUrl,
          author: note.author,
          imageUrls: note.imageUrls || [],
          videoUrl: note.videoUrl || null,
          errorMessage: null,
        };
      }
    }

    if (sawWaf) {
      return {
        ok: false,
        blocked: true,
        title: null,
        content: null,
        summary: null,
        coverImageUrl: null,
        author: null,
        imageUrls: [],
        videoUrl: null,
        errorMessage: '页面需验证，暂时无法解析正文',
      };
    }

    return {
      ok: false,
      blocked: false,
      title: null,
      content: null,
      summary: null,
      coverImageUrl: null,
      author: null,
      imageUrls: [],
      videoUrl: null,
      errorMessage: '未能提取到抖音内容',
    };
  } catch (err) {
    const aborted = err?.name === 'AbortError';
    return {
      ok: false,
      blocked: false,
      title: null,
      content: null,
      summary: null,
      coverImageUrl: null,
      author: null,
      imageUrls: [],
      videoUrl: null,
      errorMessage: aborted ? '抓取超时' : err.message || '抖音抓取失败',
    };
  }
}

module.exports = {
  extractAwemeId,
  extractDouyinFromHtml,
  fetchDouyin,
  isWafChallenge,
  preferHttps,
};
