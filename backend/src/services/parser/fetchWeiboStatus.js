/**
 * 微博：访客 cookie + m.weibo.cn statuses/show
 * 桌面 weibo.com 无登录会跳 Sina Visitor，不能直接当 HTML 抽。
 */

const MOBILE_UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) ' +
  'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 ' +
  'Mobile/15E148 Safari/604.1';

function stripHtml(html) {
  if (!html) return '';
  return String(html)
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/p>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/\n{3,}/g, '\n\n')
    .replace(/[ \t]+\n/g, '\n')
    .trim();
}

/** 从常见微博链接解析 mid / status id */
function extractWeiboStatusId(rawUrl) {
  try {
    const uri = new URL(String(rawUrl || '').trim());
    const host = uri.hostname.replace(/^www\./, '').toLowerCase();
    if (!host.includes('weibo.com') && !host.includes('weibo.cn')) {
      return null;
    }
    const path = uri.pathname.replace(/\/+$/, '');
    let m =
      path.match(/\/(?:detail|status|statuses)\/(\d{5,})/i) ||
      path.match(/\/\d+\/(\d{5,})$/) ||
      path.match(/\/(\d{16,})$/);
    if (m) return m[1];
    // query ?id=
    const qid = uri.searchParams.get('id') || uri.searchParams.get('mid');
    if (qid && /^\d{5,}$/.test(qid)) return qid;
  } catch {
    // ignore
  }
  return null;
}

async function getVisitorCookie() {
  const r1 = await fetch(
    'https://passport.weibo.com/visitor/genvisitor?cb=gen_callback&fp=%7B%22os%22%3A%221%22%7D',
    {
      headers: {
        'User-Agent': MOBILE_UA,
        Referer: 'https://weibo.com/',
      },
    },
  );
  const t1 = await r1.text();
  const tid = (t1.match(/"tid":"([^"]+)"/) || [])[1];
  if (!tid) {
    throw Object.assign(new Error('微博访客凭证获取失败'), {
      status: 502,
      code: 'WEIBO_VISITOR',
    });
  }

  const r2 = await fetch(
    `https://passport.weibo.com/visitor/visitor?a=incarnate&t=${encodeURIComponent(
      tid,
    )}&w=3&c=100&gc=&cb=cross_domain&from=weibo&_rand=${Math.random()}`,
    {
      headers: {
        'User-Agent': MOBILE_UA,
        Referer: 'https://passport.weibo.com/',
      },
    },
  );
  const t2 = await r2.text();
  const sub = (t2.match(/"sub":"([^"]+)"/) || [])[1];
  const subp = (t2.match(/"subp":"([^"]+)"/) || [])[1];
  if (!sub) {
    throw Object.assign(new Error('微博访客 cookie 获取失败'), {
      status: 502,
      code: 'WEIBO_VISITOR',
    });
  }
  return `SUB=${sub}; SUBP=${subp || ''}`;
}

async function fetchJson(url, cookie) {
  const res = await fetch(url, {
    headers: {
      'User-Agent': MOBILE_UA,
      Accept: 'application/json,text/plain,*/*',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      Cookie: cookie,
      Referer: 'https://m.weibo.cn/',
    },
  });
  const text = await res.text();
  if (/Sina Visitor System/i.test(text.slice(0, 400))) {
    throw Object.assign(new Error('微博仍要求访客验证'), {
      status: 502,
      code: 'WEIBO_VISITOR',
    });
  }
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    throw Object.assign(new Error('微博接口返回非 JSON'), {
      status: 502,
      code: 'WEIBO_PARSE',
    });
  }
  return { status: res.status, json };
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
async function fetchWeiboStatus(rawUrl) {
  const statusId = extractWeiboStatusId(rawUrl);
  if (!statusId) {
    return {
      ok: false,
      title: null,
      content: null,
      summary: null,
      coverImageUrl: null,
      author: null,
      imageUrls: [],
      videoUrl: null,
      errorMessage: '无法识别微博状态 ID',
    };
  }

  try {
    const cookie = await getVisitorCookie();
    let { json } = await fetchJson(
      `https://m.weibo.cn/statuses/show?id=${statusId}`,
      cookie,
    );

    if (!json || json.ok !== 1 || !json.data) {
      return {
        ok: false,
        title: null,
        content: null,
        summary: null,
        coverImageUrl: null,
        author: null,
        imageUrls: [],
        videoUrl: null,
        errorMessage: '微博状态不存在或不可见',
      };
    }

    let data = json.data;

    // 长文再拉全文
    if (data.isLongText) {
      try {
        const ext = await fetchJson(
          `https://m.weibo.cn/statuses/extend?id=${statusId}`,
          cookie,
        );
        const longHtml =
          ext.json?.data?.longTextContent ||
          ext.json?.data?.longText?.content ||
          null;
        if (longHtml) {
          data = { ...data, text: longHtml };
        }
      } catch {
        // 长文失败仍用短文
      }
    }

    const author = data.user?.screen_name || data.user?.name || null;
    const plain = stripHtml(data.text || data.status_title || '');
    const title =
      (data.status_title && stripHtml(data.status_title).slice(0, 40)) ||
      plain.split(/\n+/).map((s) => s.trim()).find((s) => s.length > 0)?.slice(0, 40) ||
      null;

    const imageUrls = [];
    const seen = new Set();
    const push = (u) => {
      if (!u || seen.has(u)) return;
      seen.add(u);
      imageUrls.push(u);
    };
    if (Array.isArray(data.pics)) {
      for (const p of data.pics) {
        push(p?.large?.url || p?.url || p?.bmiddle?.url);
      }
    }
    if (!imageUrls.length && data.original_pic) push(data.original_pic);
    if (!imageUrls.length && data.bmiddle_pic) push(data.bmiddle_pic);

    const videoUrl = pickWeiboVideoUrl(data.page_info);
    const pageCover =
      data.page_info?.page_pic?.url ||
      (typeof data.page_info?.page_pic === 'string'
        ? data.page_info.page_pic
        : null);
    if (!imageUrls.length && pageCover) push(pageCover);

    const bodyParts = [];
    if (author) bodyParts.push(`作者：${author}`);
    if (plain) bodyParts.push(plain);
    const content = bodyParts.join('\n\n').trim() || null;

    if (!content && imageUrls.length === 0 && !videoUrl) {
      return {
        ok: false,
        title,
        content: null,
        summary: null,
        coverImageUrl: null,
        author,
        imageUrls: [],
        videoUrl: null,
        errorMessage: '未能提取到微博正文',
      };
    }

    return {
      ok: true,
      title,
      content: content || title || (videoUrl ? '（微博视频）' : '（微博图片）'),
      summary: (plain || title || '').replace(/\s+/g, ' ').trim().slice(0, 180) || null,
      coverImageUrl: imageUrls[0] || pageCover || null,
      author,
      imageUrls: imageUrls.slice(0, 30),
      videoUrl,
      errorMessage: null,
    };
  } catch (err) {
    return {
      ok: false,
      title: null,
      content: null,
      summary: null,
      coverImageUrl: null,
      author: null,
      imageUrls: [],
      videoUrl: null,
      errorMessage: err.message || '微博抓取失败',
    };
  }
}

/** 从 page_info 取最高清晰度 MP4 */
function preferHttps(url) {
  if (!url) return null;
  let u = String(url).trim();
  if (u.startsWith('//')) u = `https:${u}`;
  if (u.startsWith('http://')) u = `https://${u.slice(7)}`;
  return u.startsWith('https://') ? u : null;
}

function pickWeiboVideoUrl(pageInfo) {
  if (!pageInfo || typeof pageInfo !== 'object') return null;
  const type = String(pageInfo.type || pageInfo.object_type || '').toLowerCase();
  const looksVideo =
    type === 'video' ||
    type === '11' ||
    pageInfo.media_info ||
    pageInfo.urls;
  if (!looksVideo && !pageInfo.media_info) return null;

  const urls = pageInfo.urls && typeof pageInfo.urls === 'object' ? pageInfo.urls : {};
  const preference = [
    'mp4_720p_mp4',
    'mp4_hd_mp4',
    'mp4_ld_mp4',
    'mp4_720p',
    'mp4_hd',
    'mp4_ld',
  ];
  for (const key of preference) {
    const u = preferHttps(urls[key]);
    if (u) return u;
  }
  for (const v of Object.values(urls)) {
    const u = preferHttps(v);
    if (u && /\.mp4(\?|$)/i.test(u)) return u;
  }

  const media = pageInfo.media_info;
  if (media && typeof media === 'object') {
    return (
      preferHttps(media.stream_url_hd) ||
      preferHttps(media.stream_url) ||
      preferHttps(media.mp4_720p_mp4) ||
      preferHttps(media.mp4_hd_url) ||
      null
    );
  }
  return null;
}

/** 从 m.weibo.cn 详情页 HTML 的 $render_data 兜底抽（本机抓到真页时） */
function extractWeiboFromHtml(html) {
  if (!html || typeof html !== 'string') return null;
  if (/Sina Visitor System/i.test(html.slice(0, 800))) return null;

  const m = html.match(/\$render_data\s*=\s*(\[[\s\S]*?\])\s*[;<]/);
  if (!m) return null;
  try {
    const arr = JSON.parse(m[1]);
    const status = arr[0]?.status || arr[0];
    if (!status || typeof status !== 'object') return null;
    const author = status.user?.screen_name || null;
    const plain = stripHtml(status.text || status.status_title || '');
    const imageUrls = [];
    if (Array.isArray(status.pics)) {
      for (const p of status.pics) {
        const u = p?.large?.url || p?.url;
        if (u && !imageUrls.includes(u)) imageUrls.push(u);
      }
    }
    const videoUrl = pickWeiboVideoUrl(status.page_info);
    const pageCover =
      status.page_info?.page_pic?.url ||
      (typeof status.page_info?.page_pic === 'string'
        ? status.page_info.page_pic
        : null);
    if (!imageUrls.length && pageCover) imageUrls.push(pageCover);

    if (!plain && !imageUrls.length && !videoUrl) return null;
    const title =
      stripHtml(status.status_title || '').slice(0, 40) ||
      plain.split(/\n+/).find((s) => s.trim())?.slice(0, 40) ||
      null;
    const parts = [];
    if (author) parts.push(`作者：${author}`);
    if (plain) parts.push(plain);
    return {
      title,
      content: parts.join('\n\n') || title || (videoUrl ? '（微博视频）' : null),
      summary: (plain || title || '').replace(/\s+/g, ' ').trim().slice(0, 180) || null,
      coverImageUrl: imageUrls[0] || pageCover || null,
      author,
      imageUrls,
      videoUrl,
    };
  } catch {
    return null;
  }
}

module.exports = {
  extractWeiboStatusId,
  fetchWeiboStatus,
  extractWeiboFromHtml,
  pickWeiboVideoUrl,
  stripHtml,
};
