const { htmlToRichText } = require('../htmlText');

/**
 * 小宇宙 xiaoyuzhoufm.com 单集页。
 * 数据在 __NEXT_DATA__.props.pageProps.episode；不取 comments。
 * 音频进 videoUrl（阅读页顶栏播放器）；Shownotes 转正文插图。
 * @type {import('./registry').PlatformAdapter}
 */

const PAGE_BASE = 'https://www.xiaoyuzhoufm.com';

function pickNextEpisode(html) {
  if (!html || typeof html !== 'string') return null;
  const m = html.match(
    /<script[^>]*id=["']__NEXT_DATA__["'][^>]*>([\s\S]*?)<\/script>/i,
  );
  if (!m) return null;
  try {
    const data = JSON.parse(m[1]);
    const episode = data?.props?.pageProps?.episode;
    return episode && typeof episode === 'object' ? episode : null;
  } catch {
    return null;
  }
}

function pickCover(episode) {
  const img = episode?.image;
  if (!img || typeof img !== 'object') return null;
  const url =
    img.largePicUrl ||
    img.middlePicUrl ||
    img.picUrl ||
    img.smallPicUrl ||
    img.thumbnailUrl ||
    null;
  return typeof url === 'string' && /^https?:\/\//i.test(url) ? url : null;
}

function pickAudioUrl(episode) {
  const candidates = [
    episode?.enclosure?.url,
    episode?.media?.source?.url,
    episode?.media?.url,
  ];
  for (const raw of candidates) {
    const url = String(raw || '').trim();
    if (/^https?:\/\//i.test(url)) return url;
  }
  return null;
}

function pickPodcastTitle(episode) {
  const title = String(episode?.podcast?.title || '').trim();
  return title || null;
}

function pickAuthor(episode) {
  const podcast = episode?.podcast;
  if (!podcast || typeof podcast !== 'object') return null;
  return (
    String(podcast.author || '').trim() ||
    String(podcast.title || '').trim() ||
    null
  );
}

function pickSummary(episode) {
  const plain = String(episode?.description || '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (!plain) return null;
  return plain.length > 200 ? `${plain.slice(0, 200)}…` : plain;
}

function buildContent(episode) {
  const shownotes = String(episode?.shownotes || '').trim();
  if (shownotes) {
    return (
      htmlToRichText(shownotes, { baseUrl: PAGE_BASE }) || null
    );
  }
  const desc = String(episode?.description || '').trim();
  if (!desc) return null;
  if (/<[a-z][\s\S]*>/i.test(desc)) {
    return htmlToRichText(desc, { baseUrl: PAGE_BASE }) || null;
  }
  return desc;
}

module.exports = {
  id: 'xiaoyuzhou',
  fetchMode: 'server',
  detectFromHtml(html) {
    return (
      typeof html === 'string' &&
      /xiaoyuzhoufm\.com/i.test(html) &&
      /id=["']__NEXT_DATA__["']/i.test(html) &&
      /"episode"\s*:/.test(html)
    );
  },
  extractMeta(html) {
    const episode = pickNextEpisode(html);
    if (!episode) return null;
    const title = String(episode.title || '').trim() || null;
    const cover = pickCover(episode);
    const podcast = pickPodcastTitle(episode);
    const summary = pickSummary(episode);
    if (!title && !cover && !episode.shownotes && !pickAudioUrl(episode)) {
      return null;
    }
    return {
      title: podcast && title ? `${title}` : title,
      summary,
      author: pickAuthor(episode),
      coverImageUrl: cover,
    };
  },
  extractContent(html) {
    const episode = pickNextEpisode(html);
    if (!episode) return null;

    // 明确不读 pageProps.comments
    const content = buildContent(episode);
    const audioUrl = pickAudioUrl(episode);
    const summary = pickSummary(episode);
    const plain = String(content || '')
      .replace(/!\[[^\]]*\]\([^)]+\)/g, '')
      .replace(/\s+/g, '');

    if (!plain && !audioUrl) return null;

    return {
      content: content || (audioUrl ? String(episode.title || '（小宇宙单集）') : null),
      summary,
      imageUrls: [],
      videoUrl: audioUrl,
    };
  },
};
