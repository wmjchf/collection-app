const DEFAULT_UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

/**
 * @param {string} url
 * @param {{ timeoutMs?: number, userAgent?: string }} [opts]
 */
async function fetchHtml(url, opts = {}) {
  const timeoutMs = opts.timeoutMs ?? 12000;
  const userAgent = opts.userAgent || DEFAULT_UA;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const res = await fetch(url, {
      redirect: 'follow',
      signal: controller.signal,
      headers: {
        'User-Agent': userAgent,
        Accept: 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Cache-Control': 'no-cache',
      },
    });

    const contentType = res.headers.get('content-type') || '';
    const html = await res.text();

    return {
      ok: res.ok,
      status: res.status,
      finalUrl: res.url || url,
      contentType,
      html,
    };
  } catch (err) {
    if (err?.name === 'AbortError') {
      throw Object.assign(new Error('抓取超时'), { status: 504, code: 'FETCH_TIMEOUT' });
    }
    throw Object.assign(new Error(`抓取失败：${err.message || '网络错误'}`), {
      status: 502,
      code: 'FETCH_FAILED',
    });
  } finally {
    clearTimeout(timer);
  }
}

module.exports = { fetchHtml, DEFAULT_UA };
