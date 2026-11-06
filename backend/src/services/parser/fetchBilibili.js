/**
 * B站：短链/视频页 → view 元数据 + playurl 整段 mp4
 * HTML 壳页通常不含直链，走公开 API 即可。
 * 多分 P：尊重 URL `?p=`，用对应 cid；无播放直链不算解析成功。
 */

const DESKTOP_UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ' +
  'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

const EMPTY = {
  ok: false,
  title: null,
  content: null,
  summary: null,
  coverImageUrl: null,
  author: null,
  imageUrls: [],
  videoUrl: null,
  errorMessage: null,
};

function preferHttps(url) {
  if (!url || typeof url !== 'string') return null;
  const u = url.trim();
  if (!u) return null;
  if (u.startsWith('//')) return `https:${u}`;
  if (u.startsWith('http://')) return `https://${u.slice(7)}`;
  return u;
}

/** 从 URL / 文本中抽出 BV 号 */
function extractBvid(raw) {
  const text = String(raw || '');
  const m = text.match(/\b(BV[\w]+)\b/i);
  return m ? m[1] : null;
}

/** 从 URL 抽出 av / aid */
function extractAid(rawUrl) {
  try {
    const uri = new URL(String(rawUrl || '').trim());
    const path = uri.pathname;
    let m = path.match(/\/av(\d+)/i) || path.match(/\/video\/(\d{5,})\/?$/i);
    if (m) return m[1];
    const q =
      uri.searchParams.get('aid') ||
      uri.searchParams.get('avid') ||
      uri.searchParams.get('av');
    if (q && /^\d{5,}$/.test(q)) return q;
  } catch {
    // ignore
  }
  return null;
}

/** 分 P：1-based；无则 1 */
function extractPageParam(rawUrl) {
  try {
    const uri = new URL(String(rawUrl || '').trim());
    const raw =
      uri.searchParams.get('p') ||
      uri.searchParams.get('page') ||
      '';
    const n = Number(raw);
    if (Number.isFinite(n) && n >= 1) return Math.floor(n);
  } catch {
    // ignore
  }
  return 1;
}

function buildVideoPageUrl(bvid, pageIndex) {
  const base = `https://www.bilibili.com/video/${bvid}`;
  const p = Number(pageIndex) || 1;
  return p > 1 ? `${base}?p=${p}` : base;
}

async function fetchJson(url, referer) {
  const res = await fetch(url, {
    headers: {
      'User-Agent': DESKTOP_UA,
      Accept: 'application/json,text/plain,*/*',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      Referer: referer || 'https://www.bilibili.com/',
    },
    redirect: 'follow',
  });
  const text = await res.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    throw Object.assign(new Error('B站接口返回非 JSON'), {
      status: 502,
      code: 'BILIBILI_PARSE',
    });
  }
  return { status: res.status, json };
}

/**
 * 短链 b23.tv 等：跟随跳转到含 BV 的页面（保留 ?p=）
 */
async function resolveVideoIdentity(rawUrl) {
  const input = String(rawUrl || '').trim();
  let page = extractPageParam(input);
  let bvid = extractBvid(input);
  if (bvid) {
    return { bvid, aid: null, page, pageUrl: buildVideoPageUrl(bvid, page) };
  }

  let aid = extractAid(input);
  if (aid) {
    return { bvid: null, aid, page, pageUrl: input };
  }

  try {
    const uri = new URL(input);
    const host = uri.hostname.replace(/^www\./, '').toLowerCase();
    if (host !== 'b23.tv' && !host.includes('bilibili.com')) {
      return { bvid: null, aid: null, page: 1, pageUrl: input };
    }

    const res = await fetch(input, {
      method: 'GET',
      redirect: 'follow',
      headers: {
        'User-Agent': DESKTOP_UA,
        Accept: 'text/html,*/*',
        Referer: 'https://www.bilibili.com/',
      },
    });
    const finalUrl = res.url || input;
    page = extractPageParam(finalUrl) || page;
    bvid = extractBvid(finalUrl);
    if (bvid) {
      return {
        bvid,
        aid: null,
        page,
        pageUrl: buildVideoPageUrl(bvid, page),
      };
    }
    aid = extractAid(finalUrl);
    if (aid) return { bvid: null, aid, page, pageUrl: finalUrl };
  } catch {
    // fall through
  }

  return { bvid: null, aid: null, page: 1, pageUrl: input };
}

/**
 * 取整段 mp4（fnval=0）。多档清晰度 + 一次短重试。
 */
async function fetchPlayMp4({ aid, bvid, cid, pageUrl }) {
  const idQs = bvid
    ? `bvid=${encodeURIComponent(bvid)}`
    : `avid=${encodeURIComponent(aid)}`;
  const referer =
    pageUrl && /bilibili\.com/i.test(pageUrl)
      ? pageUrl
      : bvid
        ? `https://www.bilibili.com/video/${bvid}`
        : 'https://www.bilibili.com/';

  const tryOnce = async () => {
    for (const qn of [80, 64, 32, 16]) {
      const { json } = await fetchJson(
        `https://api.bilibili.com/x/player/playurl?${idQs}&cid=${cid}&qn=${qn}&fnval=0&fourk=1`,
        referer,
      );
      if (json?.code !== 0) continue;
      const durl = json?.data?.durl;
      if (!Array.isArray(durl) || !durl.length) continue;
      const first = durl[0];
      const url =
        preferHttps(first.url) ||
        preferHttps((first.backup_url && first.backup_url[0]) || null);
      if (url) return url;
    }
    return null;
  };

  let url = await tryOnce();
  if (url) return url;
  await new Promise((r) => setTimeout(r, 400));
  return tryOnce();
}

/**
 * @returns {{
 *   ok: boolean,
 *   title: string|null,
 *   content: string|null,
 *   summary: string|null,
 *   coverImageUrl: string|null,
 *   author: string|null,
 *   imageUrls: string[],
 *   videoUrl: string|null,
 *   errorMessage: string|null,
 * }}
 */
async function fetchBilibili(rawUrl) {
  try {
    const id = await resolveVideoIdentity(rawUrl);
    if (!id.bvid && !id.aid) {
      return {
        ...EMPTY,
        errorMessage: '无法识别 B站 视频 ID',
      };
    }

    const viewQs = id.bvid
      ? `bvid=${encodeURIComponent(id.bvid)}`
      : `aid=${encodeURIComponent(id.aid)}`;
    const refererHint = id.pageUrl || 'https://www.bilibili.com/';

    const { json: view } = await fetchJson(
      `https://api.bilibili.com/x/web-interface/view?${viewQs}`,
      refererHint,
    );

    if (!view || view.code !== 0 || !view.data) {
      return {
        ...EMPTY,
        errorMessage: view?.message || 'B站视频不存在或不可见',
      };
    }

    const data = view.data;
    const bvid = data.bvid || id.bvid;
    const aid = data.aid || id.aid;
    const pages = Array.isArray(data.pages) ? data.pages : [];
    const pageCount = pages.length || 1;
    const pageIndex = Math.min(Math.max(Number(id.page) || 1, 1), pageCount);
    const pageMeta = pages[pageIndex - 1] || pages[0] || null;
    const cid = pageMeta?.cid || data.cid;
    const partTitle = pageMeta?.part
      ? String(pageMeta.part).trim()
      : '';
    const seriesTitle = (data.title && String(data.title).trim()) || null;
    const title =
      partTitle && pageCount > 1 && seriesTitle
        ? `${seriesTitle} · ${partTitle}`
        : seriesTitle || partTitle || null;
    const author = data.owner?.name || null;
    const desc = (data.desc && String(data.desc).trim()) || '';
    const cover = preferHttps(data.pic) || null;
    const pageUrl = bvid
      ? buildVideoPageUrl(bvid, pageIndex)
      : id.pageUrl || refererHint;

    let videoUrl = null;
    if (cid && (aid || bvid)) {
      try {
        videoUrl = await fetchPlayMp4({
          aid,
          bvid,
          cid,
          pageUrl,
        });
      } catch {
        videoUrl = null;
      }
    }

    const bodyParts = [];
    if (author) bodyParts.push(`作者：${author}`);
    if (pageCount > 1) {
      bodyParts.push(
        `分集：第 ${pageIndex} / ${pageCount} 集${
          partTitle ? ` — ${partTitle}` : ''
        }`,
      );
    }
    if (desc) bodyParts.push(desc);
    else if (seriesTitle) bodyParts.push(seriesTitle);
    const content =
      bodyParts.join('\n\n').trim() ||
      title ||
      (videoUrl ? '（B站视频）' : null);

    const summary =
      (partTitle || desc || seriesTitle || '')
        .replace(/\s+/g, ' ')
        .trim()
        .slice(0, 180) || null;

    // 顶栏视频：封面只进 cover，勿塞 imageUrls（否则无直链时被当成图集）
    if (!videoUrl) {
      return {
        ...EMPTY,
        title,
        content,
        summary,
        coverImageUrl: cover,
        author,
        imageUrls: [],
        videoUrl: null,
        pageUrl,
        errorMessage:
          '未能获取 B站 播放地址，请稍后重试或打开后点「刷新视频」',
      };
    }

    return {
      ok: true,
      title,
      content,
      summary,
      coverImageUrl: cover,
      author,
      imageUrls: [],
      videoUrl,
      pageUrl,
      errorMessage: null,
    };
  } catch (err) {
    return {
      ...EMPTY,
      errorMessage: err.message || 'B站抓取失败',
    };
  }
}

module.exports = {
  fetchBilibili,
  extractBvid,
  extractAid,
  extractPageParam,
  resolveVideoIdentity,
  buildVideoPageUrl,
};
