/**
 * B站：
 * - 视频：短链/视频页 → view 元数据 + playurl 整段 mp4；多分 P 尊重 `?p=`
 * - 图文 opus：短链或 /opus/{id} → 页面 __INITIAL_STATE__ 抽标题/正文/配图
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

function extractOpusId(raw) {
  const m = String(raw || '').match(/bilibili\.com\/opus\/(\d+)/i);
  return m ? m[1] : null;
}

function buildOpusPageUrl(opusId) {
  return `https://www.bilibili.com/opus/${opusId}`;
}

async function fetchHtml(url) {
  const res = await fetch(url, {
    method: 'GET',
    redirect: 'follow',
    headers: {
      'User-Agent': DESKTOP_UA,
      Accept: 'text/html,*/*',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      Referer: 'https://www.bilibili.com/',
    },
  });
  const html = await res.text();
  return { status: res.status, finalUrl: res.url || url, html };
}

function parseInitialState(html) {
  const raw = String(html || '');
  const m = raw.match(/__INITIAL_STATE__\s*=\s*(\{[\s\S]*?\});/);
  if (!m) return null;
  try {
    return JSON.parse(m[1]);
  } catch {
    return null;
  }
}

function nodesToPlain(nodes) {
  if (!Array.isArray(nodes)) return '';
  return nodes
    .map((n) => {
      if (!n || typeof n !== 'object') return '';
      if (n.word?.words != null) return String(n.word.words);
      if (n.rich?.text != null) return String(n.rich.text);
      if (n.formula?.latex != null) return String(n.formula.latex);
      return '';
    })
    .join('');
}

/**
 * opus 段落 → Markdown（图写进正文 ![]()，不进 imageUrls，避免当图集）
 */
function opusParagraphsToMarkdown(paragraphs) {
  const parts = [];
  const covers = [];
  for (const p of Array.isArray(paragraphs) ? paragraphs : []) {
    const type = Number(p?.para_type) || 0;
    if (type === 2 && p?.pic?.pics) {
      for (const pic of p.pic.pics) {
        const u = preferHttps(pic?.url);
        if (!u) continue;
        covers.push(u);
        parts.push(`![](${u})`);
      }
      continue;
    }
    if (type === 8 && p?.heading) {
      const level = Math.min(Math.max(Number(p.heading.level) || 1, 1), 3);
      const text = nodesToPlain(p.heading.nodes).trim();
      if (text) parts.push(`${'#'.repeat(level)} ${text}`);
      continue;
    }
    if (type === 1 && p?.text) {
      const text = nodesToPlain(p.text.nodes).trim();
      if (text) parts.push(text);
      continue;
    }
    if (p?.blockquote) {
      const text = nodesToPlain(p.blockquote.nodes || p.blockquote.text?.nodes).trim();
      if (text) parts.push(`> ${text}`);
      continue;
    }
    if (p?.list?.items && Array.isArray(p.list.items)) {
      for (const item of p.list.items) {
        const text = nodesToPlain(item?.nodes || item?.text?.nodes).trim();
        if (text) parts.push(`- ${text}`);
      }
    }
  }
  return {
    content: parts.join('\n\n').trim() || null,
    coverImageUrl: covers[0] || null,
  };
}

/** 动态顶图相册（MODULE_TYPE_TOP.album.pics），常见于纯图文动态 */
function opusTopAlbumPics(modules) {
  const top = (Array.isArray(modules) ? modules : []).find(
    (m) => m.module_type === 'MODULE_TYPE_TOP',
  );
  const pics = top?.module_top?.display?.album?.pics;
  if (!Array.isArray(pics)) return [];
  const out = [];
  for (const pic of pics) {
    const u = preferHttps(pic?.url);
    if (u) out.push(u);
  }
  return out;
}

function parseOpusFromState(state, pageUrl) {
  const detail = state?.detail;
  if (!detail || typeof detail !== 'object') {
    return {
      ...EMPTY,
      pageUrl,
      errorMessage: 'B站图文页无有效内容',
    };
  }
  const modules = Array.isArray(detail.modules) ? detail.modules : [];
  const titleMod = modules.find((m) => m.module_type === 'MODULE_TYPE_TITLE');
  const authorMod = modules.find((m) => m.module_type === 'MODULE_TYPE_AUTHOR');
  const contentMod = modules.find((m) => m.module_type === 'MODULE_TYPE_CONTENT');

  let title =
    (titleMod?.module_title?.text && String(titleMod.module_title.text).trim()) ||
    null;
  if (!title && detail.basic?.title) {
    title = String(detail.basic.title)
      .replace(/\s*-\s*哔哩哔哩\s*$/u, '')
      .trim();
  }
  const author =
    (authorMod?.module_author?.name &&
      String(authorMod.module_author.name).trim()) ||
    null;

  const topPics = opusTopAlbumPics(modules);
  const { content: bodyMd, coverImageUrl: bodyPic } = opusParagraphsToMarkdown(
    contentMod?.module_content?.paragraphs,
  );
  const bodyParts = [];
  if (author) bodyParts.push(`作者：${author}`);
  // 顶图不在段落里：写入正文，并作封面
  for (const u of topPics) {
    bodyParts.push(`![](${u})`);
  }
  if (bodyMd) bodyParts.push(bodyMd);
  const content = bodyParts.join('\n\n').trim() || title;
  const coverImageUrl = topPics[0] || bodyPic || null;
  const summary =
    (bodyMd || title || '')
      .replace(/!\[[^\]]*\]\([^)]+\)/g, ' ')
      .replace(/\s+/g, ' ')
      .trim()
      .slice(0, 180) || null;

  if (!title && !content) {
    return {
      ...EMPTY,
      pageUrl,
      errorMessage: 'B站图文内容为空',
    };
  }

  return {
    ok: true,
    title: title || 'B站图文',
    content,
    summary,
    coverImageUrl,
    author,
    imageUrls: [],
    videoUrl: null,
    pageUrl,
    errorMessage: null,
  };
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
 * 短链 b23.tv / 直链：识别视频 BV·av 或图文 opus（跳转后可带 html 复用）
 */
async function resolveBilibiliTarget(rawUrl) {
  const input = String(rawUrl || '').trim();
  let page = extractPageParam(input);

  const opusDirect = extractOpusId(input);
  if (opusDirect) {
    return {
      kind: 'opus',
      opusId: opusDirect,
      pageUrl: buildOpusPageUrl(opusDirect),
      html: null,
    };
  }

  let bvid = extractBvid(input);
  if (bvid) {
    return {
      kind: 'video',
      bvid,
      aid: null,
      page,
      pageUrl: buildVideoPageUrl(bvid, page),
      html: null,
    };
  }

  let aid = extractAid(input);
  if (aid) {
    return {
      kind: 'video',
      bvid: null,
      aid,
      page,
      pageUrl: input,
      html: null,
    };
  }

  try {
    const uri = new URL(input);
    const host = uri.hostname.replace(/^www\./, '').toLowerCase();
    if (host !== 'b23.tv' && !host.includes('bilibili.com')) {
      return { kind: 'unknown', pageUrl: input, html: null };
    }

    const fetched = await fetchHtml(input);
    const finalUrl = fetched.finalUrl || input;
    const html = fetched.html || '';

    const opusId = extractOpusId(finalUrl) || extractOpusId(html);
    if (opusId) {
      return {
        kind: 'opus',
        opusId,
        pageUrl: buildOpusPageUrl(opusId),
        html,
      };
    }

    page = extractPageParam(finalUrl) || page;
    bvid = extractBvid(finalUrl) || extractBvid(html);
    if (bvid) {
      return {
        kind: 'video',
        bvid,
        aid: null,
        page,
        pageUrl: buildVideoPageUrl(bvid, page),
        html: null,
      };
    }
    aid = extractAid(finalUrl);
    if (aid) {
      return {
        kind: 'video',
        bvid: null,
        aid,
        page,
        pageUrl: finalUrl,
        html: null,
      };
    }
  } catch {
    // fall through
  }

  return { kind: 'unknown', pageUrl: input, html: null };
}

/** @deprecated 兼容旧调用：仅视频身份 */
async function resolveVideoIdentity(rawUrl) {
  const t = await resolveBilibiliTarget(rawUrl);
  if (t.kind === 'video') {
    return {
      bvid: t.bvid,
      aid: t.aid,
      page: t.page,
      pageUrl: t.pageUrl,
    };
  }
  return { bvid: null, aid: null, page: 1, pageUrl: t.pageUrl || rawUrl };
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
async function fetchBilibiliVideo(id) {
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
  const partTitle = pageMeta?.part ? String(pageMeta.part).trim() : '';
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
}

async function fetchBilibiliOpus(target) {
  const pageUrl = target.pageUrl || buildOpusPageUrl(target.opusId);
  let html = target.html;
  if (!html) {
    const fetched = await fetchHtml(pageUrl);
    html = fetched.html;
  }
  const state = parseInitialState(html);
  if (!state) {
    return {
      ...EMPTY,
      pageUrl,
      errorMessage: 'B站图文页解析失败',
    };
  }
  return parseOpusFromState(state, pageUrl);
}

async function fetchBilibili(rawUrl) {
  try {
    const target = await resolveBilibiliTarget(rawUrl);
    if (target.kind === 'opus') {
      return fetchBilibiliOpus(target);
    }
    if (target.kind === 'video' && (target.bvid || target.aid)) {
      return fetchBilibiliVideo(target);
    }
    return {
      ...EMPTY,
      errorMessage: '无法识别 B站 链接（需视频或图文 opus）',
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
  extractOpusId,
  extractPageParam,
  resolveVideoIdentity,
  resolveBilibiliTarget,
  buildVideoPageUrl,
  buildOpusPageUrl,
};
