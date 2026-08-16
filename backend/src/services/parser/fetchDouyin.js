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
      path.match(/\/slides\/(\d{5,})/i) ||
      path.match(/\/share\/slides\/(\d{5,})/i) ||
      path.match(/\/note\/(\d{5,})/i) ||
      path.match(/\/share\/note\/(\d{5,})/i);
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

function isNoteOrSlidesUrl(rawUrl) {
  try {
    const path = new URL(String(rawUrl || '').trim()).pathname;
    return /\/note\//i.test(path) || /\/slides\//i.test(path);
  } catch {
    return false;
  }
}

function isJunkMediaUrl(url) {
  return /logo_launcher|fe_app_new|\/eden-cn\/[^"'\\\s]*logo/i.test(
    String(url || ''),
  );
}

function hasRealMedia(note) {
  if (!note) return false;
  if (note.videoUrl) return true;
  const imgs = (note.imageUrls || []).filter(
    (u) => u && !isJunkMediaUrl(u),
  );
  return imgs.length > 0;
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
  if (typeof obj === 'string') return preferHttps(obj);
  const list = obj.url_list || obj.urlList || obj.uri_list;
  if (Array.isArray(list)) {
    for (const raw of list) {
      const https =
        typeof raw === 'string'
          ? preferHttps(raw)
          : preferHttps(raw?.url || raw?.uri || null);
      if (https) return https;
    }
  }
  return preferHttps(obj.url || obj.uri || null);
}

function pickImageUrl(img) {
  if (!img) return null;
  if (typeof img === 'string') return preferHttps(img);
  return (
    firstUrlList(img) ||
    firstUrlList(img.display_image || img.displayImage) ||
    firstUrlList(img.owner_watermark_image || img.ownerWatermarkImage) ||
    firstUrlList(img.origin_thumb || img.thumb) ||
    firstUrlList(
      img.download_url_list ? { url_list: img.download_url_list } : null,
    ) ||
    firstUrlList(
      img.downloadUrlList ? { url_list: img.downloadUrlList } : null,
    ) ||
    preferHttps(img.url)
  );
}

function collectGallery(aweme) {
  const gallery = [];
  const src = [];
  const pushAll = (arr) => {
    if (Array.isArray(arr)) src.push(...arr);
  };
  pushAll(aweme.images);
  pushAll(aweme.image_list);
  pushAll(aweme.imageList);
  if (aweme.image_post_info) {
    pushAll(aweme.image_post_info.images);
    pushAll(aweme.image_post_info.image_list);
  }
  if (aweme.imagePostInfo) {
    pushAll(aweme.imagePostInfo.images);
    pushAll(aweme.imagePostInfo.image_list);
  }
  for (const img of src) {
    const https = preferHttps(pickImageUrl(img));
    if (https && !isJunkMediaUrl(https) && !gallery.includes(https)) {
      gallery.push(https);
    }
  }
  return gallery;
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
    const sorted = [...video.bit_rate].sort(
      (a, b) => (Number(b.bit_rate) || 0) - (Number(a.bit_rate) || 0),
    );
    for (const br of sorted) {
      videoUrl = firstUrlList(br.play_addr || br.playAddr);
      if (videoUrl) break;
    }
  }

  const gallery = collectGallery(aweme);

  // 是否丢掉 videoUrl 由调用方按路径决定（note/slides vs video），这里有图也保留 play_addr

  const coverCandidates = [
    gallery[0],
    firstUrlList(video.cover),
    firstUrlList(video.origin_cover),
    firstUrlList(video.dynamic_cover),
  ]
    .map((u) => preferHttps(u))
    .filter((u) => u && !isJunkMediaUrl(u));
  const coverImageUrl = coverCandidates[0] || null;

  // 纯视频：imageUrls 空，封面单独在 coverImageUrl
  // 图文：imageUrls = 图集
  const imageUrls =
    gallery.length > 0
      ? gallery
      : !videoUrl && coverImageUrl
        ? [coverImageUrl]
        : [];

  const title =
    (desc.split(/\n+/).map((s) => s.trim()).find(Boolean) || '').slice(0, 40) ||
    (author ? `${author}的抖音` : null);

  const parts = [];
  if (author) parts.push(`作者：${author}`);
  if (desc) parts.push(desc);
  const content = parts.join('\n\n').trim() || null;

  if (!content && !imageUrls.length && !videoUrl && !coverImageUrl) return null;

  const awemeId = String(aweme.aweme_id || aweme.awemeId || aweme.id || '');

  return {
    title,
    content:
      content || title || (videoUrl ? '（抖音视频）' : '（抖音图片）'),
    summary:
      (desc || title || '').replace(/\s+/g, ' ').trim().slice(0, 180) || null,
    coverImageUrl,
    author,
    imageUrls,
    videoUrl,
    awemeId,
  };
}

function betterPick(a, b, wantId) {
  if (!a) return b;
  if (!b) return a;
  const aN = a.imageUrls?.length || 0;
  const bN = b.imageUrls?.length || 0;
  if (wantId) {
    const aHit = a.awemeId && String(a.awemeId) === String(wantId);
    const bHit = b.awemeId && String(b.awemeId) === String(wantId);
    if (aHit && !bHit) return a;
    if (bHit && !aHit) return b;
  }
  if (bN !== aN) return bN > aN ? b : a;
  if (!!b.videoUrl !== !!a.videoUrl) return b.videoUrl ? b : a;
  return a;
}

function findAwemeInTree(node, depth = 0, wantId = null) {
  if (!node || typeof node !== 'object' || depth > 12) return null;
  let best = null;
  const consider = (p) => {
    if (p) best = betterPick(best, p, wantId);
  };
  if (
    (node.video ||
      Array.isArray(node.images) ||
      Array.isArray(node.image_list) ||
      node.image_post_info ||
      node.imagePostInfo) &&
    (node.desc != null ||
      node.author ||
      node.aweme_id ||
      node.awemeId ||
      node.id)
  ) {
    consider(pickFromAweme(node));
  }
  if (Array.isArray(node.item_list) && node.item_list[0]) {
    consider(pickFromAweme(node.item_list[0]));
  }
  if (node.aweme_detail) consider(pickFromAweme(node.aweme_detail));
  if (node.awemeDetail) consider(pickFromAweme(node.awemeDetail));
  if (Array.isArray(node)) {
    for (const x of node) {
      consider(findAwemeInTree(x, depth + 1, wantId));
    }
    return best;
  }
  for (const v of Object.values(node)) {
    if (v && typeof v === 'object') {
      consider(findAwemeInTree(v, depth + 1, wantId));
    }
  }
  return best;
}

/** 从分享页 / 本机回传 HTML 抽取 */
function extractDouyinFromHtml(html, opts = {}) {
  if (!html || typeof html !== 'string') return null;
  if (isWafChallenge(html)) return null;

  const wantId =
    opts.wantId ||
    extractAwemeId(opts.pageUrl) ||
    extractAwemeId(opts.baseUrl) ||
    extractAwemeId(opts.finalUrl) ||
    (() => {
      const m = String(html).match(
        /\/(?:share\/)?(?:note|slides|video)\/(\d{5,})/i,
      );
      return m ? m[1] : null;
    })();

  // App WebView 注入的抽取块
  const injected = html.match(
    /<script[^>]*id=["']SC_DOUYIN_EXTRACT["'][^>]*>([\s\S]*?)<\/script>/i,
  );
  if (injected) {
    try {
      const data = JSON.parse(injected[1].trim());
      const videoUrl = preferHttps(data.videoUrl);
      const coverRaw = preferHttps(data.cover);
      const cover =
        coverRaw && !isJunkMediaUrl(coverRaw) ? coverRaw : null;
      const desc = data.desc ? String(data.desc).trim() : '';
      const author = data.author ? String(data.author).trim() : null;
      const title =
        (data.title ? String(data.title).trim().slice(0, 80) : null) ||
        (desc.split(/\n+/).map((s) => s.trim()).find(Boolean) || '').slice(0, 40) ||
        null;
      const imageUrls = [];
      const pushImg = (u) => {
        const https = preferHttps(u);
        if (https && !isJunkMediaUrl(https) && !imageUrls.includes(https)) {
          imageUrls.push(https);
        }
      };
      if (Array.isArray(data.imageUrls)) {
        for (const u of data.imageUrls) pushImg(u);
      }
      // 媒体类型跟 pageKind/路径：note|slides 清 video；有图集不自动清 videoUrl
      const pageKind = String(data.pageKind || '').toLowerCase();
      const noteLike =
        pageKind === 'note' || pageKind === 'slides';
      const finalVideo = noteLike ? null : videoUrl;
      if (!finalVideo && cover && !imageUrls.length) pushImg(cover);
      if (finalVideo || imageUrls.length || cover || title || desc) {
        if (!finalVideo && !imageUrls.length && !cover) {
          // 仅标题文案、无媒体：当作没抽到（note 壳页）
        } else {
          const parts = [];
          if (author) parts.push(`作者：${author}`);
          if (desc) parts.push(desc);
          else if (title) parts.push(title);
          return {
            title: title || (author ? `${author}的抖音` : null),
            content:
              parts.join('\n\n').trim() ||
              title ||
              (finalVideo ? '（抖音视频）' : '（抖音图文）'),
            summary:
              (desc || title || '').replace(/\s+/g, ' ').trim().slice(0, 180) ||
              null,
            coverImageUrl: cover || imageUrls[0] || null,
            author,
            imageUrls: imageUrls.slice(0, 30),
            videoUrl: finalVideo,
          };
        }
      }
    } catch {
      // fall through
    }
  }

  const router = parseRouterData(html);
  if (router) {
    const fromRouter = findAwemeInTree(
      router.loaderData || router,
      0,
      wantId,
    );
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
  const coverRaw = preferHttps(ogImage);
  const cover =
    coverRaw && !isJunkMediaUrl(coverRaw) ? coverRaw : null;
  const title = ogTitle ? String(ogTitle).trim().slice(0, 80) : null;
  if (!videoUrl && !cover && !title) return null;

  return {
    title,
    content: title || (videoUrl ? '（抖音视频）' : null),
    summary: title,
    coverImageUrl: cover,
    author: null,
    imageUrls: cover && !videoUrl ? [cover] : [],
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
    const noteLike =
      isNoteOrSlidesUrl(shareUrl) || isNoteOrSlidesUrl(rawUrl);

    // 优先保留短链重定向后的带签 URL；note 不要硬改成 video
    const candidates = [];
    const pushUnique = (u) => {
      if (u && !candidates.includes(u)) candidates.push(u);
    };
    pushUnique(shareUrl);
    if (awemeId) {
      if (noteLike) {
        pushUnique(
          `https://www.iesdouyin.com/share/note/${awemeId}/?from_ssr=1`,
        );
      } else {
        pushUnique(`https://www.iesdouyin.com/share/video/${awemeId}/`);
        pushUnique(`https://m.douyin.com/share/video/${awemeId}`);
      }
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
      const note = extractDouyinFromHtml(lastHtml, {
        wantId: awemeId,
        finalUrl,
      });
      if (note && hasRealMedia(note)) {
        const pathNote =
          noteLike || isNoteOrSlidesUrl(finalUrl);
        return {
          ok: true,
          blocked: false,
          title: note.title,
          content: note.content,
          summary: note.summary,
          coverImageUrl: note.coverImageUrl,
          author: note.author,
          imageUrls: note.imageUrls || [],
          // note/slides 按路径丢掉误带的 play_addr；video 页即使有图也保留
          videoUrl: pathNote ? null : note.videoUrl || null,
          errorMessage: null,
        };
      }
      // note/slides：SSR 常无正文，必须本机 WebView
      if (noteLike || isNoteOrSlidesUrl(finalUrl)) {
        return {
          ok: false,
          blocked: true,
          title: note?.title || null,
          content: null,
          summary: null,
          coverImageUrl: null,
          author: null,
          imageUrls: [],
          videoUrl: null,
          errorMessage: '图文页需本机加载',
        };
      }
    }

    if (sawWaf || noteLike) {
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
        errorMessage: sawWaf
          ? '页面需验证，暂时无法解析正文'
          : '图文页需本机加载',
      };
    }

    // 视频分享页 SSR 常只剩壳（有 itemId、无 aweme/play_addr），需本机 WebView
    if (awemeId || /\/share\/video\//i.test(shareUrl || '')) {
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
        errorMessage: '视频页需本机加载',
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
  isNoteOrSlidesUrl,
  isWafChallenge,
  preferHttps,
};
