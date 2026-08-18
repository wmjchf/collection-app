/** 共享：HTML 片段转纯文本 / 带内嵌图与基础样式的正文 */

function absolutize(baseUrl, src) {
  if (!src) return null;
  const raw = String(src).trim();
  if (!raw || raw.startsWith('data:')) return null;
  try {
    return new URL(raw, baseUrl || undefined).href;
  } catch {
    return raw.startsWith('//') ? `https:${raw}` : raw;
  }
}

function imgSrc($el) {
  return (
    $el.attr('data-src') ||
    $el.attr('data-original') ||
    $el.attr('data-lazy-src') ||
    $el.attr('src') ||
    null
  );
}

function escapeMdInline(text) {
  return String(text || '')
    .replace(/\*/g, '')
    .replace(/\{\{/g, '')
    .replace(/\}\}/g, '')
    .replace(/\n+/g, ' ')
    .trim();
}

function depth(el) {
  let d = 0;
  let n = el;
  while (n && n.parent) {
    d += 1;
    n = n.parent;
  }
  return d;
}

function parseStyleAttrs($el, tagName) {
  const style = String($el.attr('style') || '').toLowerCase();
  const tag = (tagName || '').toLowerCase();

  let weightRaw =
    ($el.attr('font-weight') || '').toLowerCase() ||
    (style.match(/font-weight\s*:\s*([^;]+)/) || [])[1] ||
    '';
  weightRaw = String(weightRaw).trim().toLowerCase();

  let sizeRaw =
    ($el.attr('font-size') || '').toLowerCase() ||
    (style.match(/font-size\s*:\s*([^;]+)/) || [])[1] ||
    '';
  sizeRaw = String(sizeRaw).trim().toLowerCase();

  // 旧式 <font size="4">
  const fontSizeAttr = $el.attr('size');
  if (!sizeRaw && fontSizeAttr && tag === 'font') {
    const n = parseInt(fontSizeAttr, 10);
    if (!Number.isNaN(n)) {
      // HTML font size 1–7 ≈ 10–48px
      sizeRaw = `${Math.round(10 + n * 4)}px`;
    }
  }

  // 语义加粗 vs 样式加粗分开：微信正文常写 font-weight:bold 但视觉仍像常规字重
  const semanticBold = tag === 'strong' || tag === 'b';
  let styleBold =
    weightRaw === 'bold' || weightRaw === 'bolder';
  if (!styleBold && weightRaw) {
    const n = parseInt(weightRaw, 10);
    if (!Number.isNaN(n) && n >= 600) styleBold = true;
  }

  const italic =
    tag === 'em' ||
    tag === 'i' ||
    /font-style\s*:\s*italic/.test(style);

  let sizePx = null;
  if (sizeRaw) {
    const px = sizeRaw.match(/^([\d.]+)\s*px/);
    const pt = sizeRaw.match(/^([\d.]+)\s*pt/);
    const em = sizeRaw.match(/^([\d.]+)\s*em/);
    const rem = sizeRaw.match(/^([\d.]+)\s*rem/);
    const pct = sizeRaw.match(/^([\d.]+)\s*%/);
    if (px) sizePx = parseFloat(px[1]);
    else if (pt) sizePx = parseFloat(pt[1]) * (96 / 72);
    else if (em) sizePx = parseFloat(em[1]) * 16;
    else if (rem) sizePx = parseFloat(rem[1]) * 16;
    else if (pct) sizePx = (parseFloat(pct[1]) / 100) * 16;
  }

  return { semanticBold, styleBold, italic, sizePx };
}

/** 微信正文基准常为 17px；字号强调须 ≥18 */
const EMPHASIS_SIZE_MIN = 18;

function isBlockTag(tag) {
  return tag === 'section' || tag === 'div' || tag === 'p';
}

function isInlineStyleTag(tag) {
  return (
    tag === 'span' ||
    tag === 'font' ||
    tag === 'strong' ||
    tag === 'b' ||
    tag === 'em' ||
    tag === 'i'
  );
}

function plainLen(text) {
  return String(text || '')
    .replace(/!\[[^\]]*\]\([^)]+\)/g, '')
    .replace(/\{\{\d+\|/g, '')
    .replace(/\}\}/g, '')
    .replace(/\*\*/g, '')
    .replace(/(?<!\*)\*(?!\*)/g, '')
    .replace(/#{1,4}\s+/g, '')
    .replace(/\s+/g, '')
    .length;
}

function stripBoldMarkers(text) {
  return String(text || '')
    .replace(/^\*\*([\s\S]*)\*\*$/, '$1')
    .replace(/\*\*/g, '');
}

function stripItalicMarkers(text) {
  return String(text || '').replace(
    /^\*(?!\*)([\s\S]*?)\*(?!\*)$/,
    '$1',
  );
}

function stripSizeMarkers(text) {
  return String(text || '').replace(/\{\{(\d+)\|([\s\S]*?)\}\}/g, '$2');
}

function stripHeadingMarkers(text) {
  return String(text || '')
    .replace(/^\s*#{1,4}\s+/, '')
    .trim();
}

function isMostlyImage(text) {
  const t = String(text || '').trim();
  return /^!\[[^\]]*\]\([^)]+\)$/.test(t);
}

function headingLevelFromSize(px) {
  if (px >= 24) return 1;
  if (px >= 20) return 2;
  if (px >= 18) return 3;
  return 4;
}

function alreadyBoldWrapped(text) {
  const t = String(text || '').trim();
  return /^\*\*[\s\S]+\*\*$/.test(t);
}

function alreadySizeWrapped(text) {
  const t = String(text || '').trim();
  return /^\{\{\d+\|[\s\S]+\}\}$/.test(t);
}

function alreadyHeading(text) {
  return /^\s*#{1,4}\s+\S/.test(String(text || ''));
}

/**
 * 纯文本：去掉标签，保留换段。图片与样式不保留。
 */
function htmlToText(fragment) {
  const cheerio = require('cheerio');
  const $ = cheerio.load(`<div id="__root">${fragment}</div>`, {
    decodeEntities: true,
  });
  $('#__root script, #__root style, #__root noscript').remove();
  $('#__root br').replaceWith('\n');
  $('#__root p, #__root div, #__root li, #__root h1, #__root h2, #__root h3, #__root h4').each(
    (_, el) => {
      $(el).append('\n\n');
    },
  );
  let text = $('#__root').text();
  text = text
    .replace(/\u00a0/g, ' ')
    .replace(/[ \t]+\n/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
  return text;
}

/**
 * 文章正文：只保留基础样式与排版（不加正文插图）。
 * - 标题：# / ## / ###
 * - 加粗：**text**  斜体：*text*
 * - 行内偏大字号：{{18|text}}
 * 封面仍走 meta.coverImageUrl；图集类内容走 imageUrls，不经此函数。
 */
function htmlToRichText(fragment, { baseUrl } = {}) {
  const cheerio = require('cheerio');
  const $ = cheerio.load(`<div id="__root">${fragment}</div>`, {
    decodeEntities: true,
  });
  $('#__root script, #__root style, #__root noscript').remove();

  // 正文阅读不插图：直接去掉 img（避免 ![image] 占位）
  $('#__root img').remove();

  // 2) 语义标题
  for (const [sel, level] of [
    ['h1', 1],
    ['h2', 2],
    ['h3', 3],
    ['h4', 4],
  ]) {
    $(`#__root ${sel}`).each((_, el) => {
      const t = $(el).text().replace(/\s+/g, ' ').trim();
      if (!t) {
        $(el).remove();
        return;
      }
      $(el).replaceWith(`\n\n${'#'.repeat(level)} ${escapeMdInline(t)}\n\n`);
    });
  }

  // 3) style / 语义加粗斜体：由内到外
  // - section/div/p：只做「短伪标题」提升，绝不整块包 ** / {{N|}}（避免正文 17px 容器误伤）
  // - span/font/strong…：行内样式；字号强调须 ≥18；样式加粗在正文尺寸(≤17)上忽略
  const styleNodes = $(
    '#__root span, #__root font, #__root strong, #__root b, #__root em, #__root i, #__root section, #__root p, #__root div',
  ).toArray();
  styleNodes.sort((a, b) => depth(b) - depth(a));

  for (const el of styleNodes) {
    const $el = $(el);
    if (!$el.parent().length) continue;
    const tag = (el.tagName || el.name || '').toLowerCase();
    const { semanticBold, styleBold, italic, sizePx } = parseStyleAttrs(
      $el,
      tag,
    );

    const emphasizedSize =
      sizePx != null && sizePx >= EMPHASIS_SIZE_MIN;
    // 样式 bold 仅在明显大于正文时采纳；语义 <strong>/<b> 始终算加粗
    const bold =
      semanticBold ||
      (styleBold && emphasizedSize);

    const block = isBlockTag(tag);
    const inline = isInlineStyleTag(tag);

    if (block) {
      // 块级：仅短+大号+加粗 → 标题
      let raw = $el
        .text()
        .replace(/\u00a0/g, ' ')
        .replace(/[ \t]+\n/g, '\n')
        .replace(/\n{3,}/g, '\n\n')
        .trim();
      if (!raw || isMostlyImage(raw) || alreadyHeading(raw)) continue;
      const len = plainLen(raw);
      const singleLine = !/\n/.test(raw);
      const headingCandidate =
        (bold || styleBold || semanticBold) &&
        emphasizedSize &&
        singleLine &&
        len > 0 &&
        len <= 40;
      if (!headingCandidate) continue;
      const level = headingLevelFromSize(sizePx);
      const title = escapeMdInline(
        stripHeadingMarkers(
          stripSizeMarkers(stripBoldMarkers(stripItalicMarkers(raw))),
        ),
      );
      if (!title) continue;
      $el.replaceWith(`\n\n${'#'.repeat(level)} ${title}\n\n`);
      continue;
    }

    if (!inline) continue;

    if (
      !bold &&
      !italic &&
      !emphasizedSize &&
      !semanticBold &&
      tag !== 'em' &&
      tag !== 'i'
    ) {
      continue;
    }

    let raw = $el
      .text()
      .replace(/\u00a0/g, ' ')
      .replace(/[ \t]+\n/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
    if (!raw || isMostlyImage(raw) || alreadyHeading(raw)) continue;

    const len = plainLen(raw);
    if (len === 0) continue;

    // 行内标签不做标题提升（避免打断「……和<span>小标题</span>。」这类句子）
    let out = raw;

    // 行内偏大字号（正文 17px 不进这里）
    if (emphasizedSize && !alreadySizeWrapped(out)) {
      const inner = stripSizeMarkers(out);
      out = `{{${Math.round(sizePx)}|${inner}}}`;
    }

    if (bold && !alreadyBoldWrapped(stripSizeMarkers(out))) {
      const sizeM = out.match(/^\{\{(\d+)\|([\s\S]*)\}\}$/);
      if (sizeM) {
        const inner = stripBoldMarkers(sizeM[2]);
        out = `{{${sizeM[1]}|**${inner}**}}`;
      } else if (!alreadyBoldWrapped(out)) {
        out = `**${stripBoldMarkers(out)}**`;
      }
    }

    if (italic) {
      const sizeM = out.match(/^\{\{(\d+)\|([\s\S]*)\}\}$/);
      if (sizeM) {
        let inner = sizeM[2];
        if (
          !/^\*(?!\*)[\s\S]+\*(?!\*)$/.test(inner) &&
          !alreadyBoldWrapped(inner)
        ) {
          inner = `*${stripItalicMarkers(inner)}*`;
        }
        out = `{{${sizeM[1]}|${inner}}}`;
      } else if (
        !/^\*(?!\*)[\s\S]+\*(?!\*)$/.test(out) &&
        !alreadyBoldWrapped(out)
      ) {
        out = `*${stripItalicMarkers(out)}*`;
      }
    }

    if (out !== raw) {
      $el.replaceWith(out);
    }
  }

  $('#__root br').replaceWith('\n');
  $('#__root p, #__root div, #__root li, #__root section').each((_, el) => {
    $(el).append('\n\n');
  });

  let text = $('#__root').text();
  text = text
    .replace(/\u00a0/g, ' ')
    .replace(/[ \t]+\n/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    // 清理可能叠出的空标题/空加粗
    .replace(/\*\*\s*\*\*/g, '')
    .replace(/\{\{\d+\|\s*\}\}/g, '')
    .trim();
  return text;
}

module.exports = { htmlToText, htmlToRichText, absolutize };
