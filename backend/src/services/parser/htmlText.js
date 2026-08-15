/** 共享：HTML 片段转纯文本（微信正文等） */
function htmlToText(fragment) {
  const cheerio = require('cheerio');
  const $ = cheerio.load(`<div id="__root">${fragment}</div>`, {
    decodeEntities: true,
  });
  $('#__root script, #__root style, #__root noscript').remove();
  $('#__root br').replaceWith('\n');
  $('#__root p, #__root div, #__root li, #__root h1, #__root h2, #__root h3').each(
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

module.exports = { htmlToText };
