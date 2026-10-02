const cheerio = require('cheerio');
const { htmlToRichText, absolutize } = require('./htmlText');

/**
 * 豆瓣小组话题：正文在 #link-report .topic-richtext；勿吞评论/侧栏/头像。
 */

function isJunkImageUrl(src) {
  const u = String(src || '').toLowerCase();
  if (!u) return true;
  if (u.includes('douban_error') || u.includes('/icon/')) return true;
  if (/\/view\/group\/s?q?x?s?\//i.test(u) && !/group_topic/i.test(u)) {
    // 小组方图 / 小图常作侧栏装饰，不当帖图
    if (/\/view\/group\/(?:sqxs|s|m)\//i.test(u)) return true;
  }
  return false;
}

function preferLargeTopicImage(src) {
  const u = String(src || '');
  // l/public 比 m/s 清晰
  return u.replace(/\/view\/group_topic\/[a-z]\//i, '/view/group_topic/l/');
}

function pickTopicRoot($) {
  const rich = $('#link-report .topic-richtext').first();
  if (rich.length) return rich;
  const report = $('#link-report').first();
  if (report.length) return report;
  return null;
}

/**
 * @param {string} html
 * @param {{ baseUrl?: string }} [opts]
 * @returns {{
 *   noteId: string|null,
 *   title: string|null,
 *   author: string|null,
 *   content: string|null,
 *   summary: string|null,
 *   coverImageUrl: string|null,
 *   imageUrls: string[],
 *   videoUrl: null,
 * } | null}
 */
function extractDoubanTopic(html, opts = {}) {
  if (!html || typeof html !== 'string') return null;
  if (html.includes('没有访问权限') && !html.includes('topic-richtext')) {
    return null;
  }

  const $ = cheerio.load(html);
  const root = pickTopicRoot($);
  if (!root || !root.length) return null;

  // 去掉可能误嵌的评论块
  root.find('#comments, .topic-reply, .comment-item, .aside').remove();

  const title =
    $('h1').first().text().replace(/\s+/g, ' ').trim() ||
    $('meta[property="og:title"]').attr('content')?.trim() ||
    null;
  const author =
    $('.topic-doc .from a').first().text().replace(/\s+/g, ' ').trim() ||
    null;

  const baseUrl = opts.baseUrl || 'https://www.douban.com/';
  const fragment = $.html(root);
  let content = htmlToRichText(fragment, { baseUrl }) || null;

  const imageUrls = [];
  root.find('img').each((_, el) => {
    const raw =
      $(el).attr('data-src') ||
      $(el).attr('data-original') ||
      $(el).attr('src');
    const abs = absolutize(baseUrl, raw);
    if (!abs || isJunkImageUrl(abs)) return;
    const large = preferLargeTopicImage(abs);
    if (!imageUrls.includes(large)) imageUrls.push(large);
  });

  // 正文里已有 ![]()；图集字段留空，避免顶栏再轮播一遍（帖图与文字交错）
  // 封面取第一张帖图
  const coverImageUrl =
    imageUrls[0] ||
    absolutize(
      baseUrl,
      $('meta[property="og:image"]').attr('content') || null,
    );

  if (coverImageUrl && isJunkImageUrl(coverImageUrl)) {
    // og 可能是小组图
  }

  const plain = root.text().replace(/\s+/g, ' ').trim();
  if (!plain && !imageUrls.length) return null;

  const summary = plain.slice(0, 500) || null;
  if (!content && plain) content = plain;

  return {
    noteId: null,
    title,
    author,
    content,
    summary,
    coverImageUrl:
      coverImageUrl && !isJunkImageUrl(coverImageUrl) ? coverImageUrl : imageUrls[0] || null,
    imageUrls: [],
    videoUrl: null,
  };
}

module.exports = {
  extractDoubanTopic,
  isJunkImageUrl,
  preferLargeTopicImage,
};
