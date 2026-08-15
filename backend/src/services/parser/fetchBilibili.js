/**
 * B站：短链/视频页 → view 元数据 + playurl 整段 mp4
 * HTML 壳页通常不含直链，走公开 API 即可。
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
 * 短链 b23.tv 等：跟随跳转到含 BV 的页面
 */
async function resolveVideoIdentity(rawUrl) {
  const input = String(rawUrl || '').trim();
  let bvid = extractBvid(input);
  if (bvid) return { bvid, aid: null, pageUrl: input };

  let aid = extractAid(input);
  if (aid) return { bvid: null, aid, pageUrl: input };

  try {
    const uri = new URL(input);
    const host = uri.hostname.replace(/^www\./, '').toLowerCase();
    if (host !== 'b23.tv' && !host.includes('bilibili.com')) {
      return { bvid: null, aid: null, pageUrl: input };
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
    bvid = extractBvid(finalUrl);
    if (bvid) return { bvid, aid: null, pageUrl: finalUrl };
    aid = extractAid(finalUrl);
    if (aid) return { bvid: null, aid, pageUrl: finalUrl };
  } catch {
    // fall through
  }

  return { bvid: null, aid: null, pageUrl: input };
}

/**
 * 取整段 mp4（fnval=0）。优先中等清晰度，失败再降级。
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

  for (const qn of [64, 32, 16]) {
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
    const referer = id.bvid
      ? `https://www.bilibili.com/video/${id.bvid}`
      : id.pageUrl || 'https://www.bilibili.com/';

    const { json: view } = await fetchJson(
      `https://api.bilibili.com/x/web-interface/view?${viewQs}`,
      referer,
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
    const cid = pages[0]?.cid || data.cid;
    const title = (data.title && String(data.title).trim()) || null;
    const author = data.owner?.name || null;
    const desc = (data.desc && String(data.desc).trim()) || '';
    const cover = preferHttps(data.pic) || null;

    let videoUrl = null;
    if (cid && (aid || bvid)) {
      try {
        videoUrl = await fetchPlayMp4({
          aid,
          bvid,
          cid,
          pageUrl: referer,
        });
      } catch {
        // 元数据仍可用
      }
    }

    const bodyParts = [];
    if (author) bodyParts.push(`作者：${author}`);
    if (desc) bodyParts.push(desc);
    else if (title) bodyParts.push(title);
    const content =
      bodyParts.join('\n\n').trim() ||
      title ||
      (videoUrl ? '（B站视频）' : null);

    if (!content && !cover && !videoUrl) {
      return {
        ...EMPTY,
        title,
        author,
        errorMessage: '未能提取到 B站 内容',
      };
    }

    const summary =
      (desc || title || '').replace(/\s+/g, ' ').trim().slice(0, 180) || null;

    return {
      ok: true,
      title,
      content,
      summary,
      coverImageUrl: cover,
      author,
      imageUrls: cover ? [cover] : [],
      videoUrl,
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
  resolveVideoIdentity,
};
