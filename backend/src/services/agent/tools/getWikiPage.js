const wikiStore = require('../../wiki/wikiStore');

const tool = {
  name: 'get_wiki_page',
  stage: 'P1',
  mutates: false,
  schema: {
    type: 'object',
    properties: {
      slug: { type: 'string' },
      pageId: { type: 'number' },
      kind: { type: 'string' },
      maxChars: { type: 'number' },
    },
  },
  /**
   * 读 Wiki 页（实体/概念/源页/目录）；仅助手用。
   * @param {{ userId: number }} ctx
   * @param {{ slug?: string, pageId?: number, kind?: string, maxChars?: number }} args
   */
  async execute(ctx, args) {
    const page = await wikiStore.getPage(ctx.userId, {
      pageId: args?.pageId,
      slug: args?.slug,
      kind: args?.kind,
    });
    if (!page) {
      return { ok: false, error: 'not_found' };
    }

    const maxChars = Math.min(
      Math.max(Number(args?.maxChars) || 4000, 200),
      20000,
    );
    let body = String(page.body || '');
    if (body.length > maxChars) {
      body = `${body.slice(0, maxChars)}…`;
    }

    let related = [];
    if (page.kind === 'source') {
      related = await wikiStore.listLinkedEntities(ctx.userId, page.id, 8);
    } else if (page.kind === 'entity' || page.kind === 'concept') {
      related = await wikiStore.listLinkedSources(ctx.userId, page.id, 8);
    }

    return {
      ok: true,
      data: {
        pageId: page.id,
        kind: page.kind,
        slug: page.slug,
        title: page.title,
        summary: page.summary,
        body,
        itemId: page.item_id || null,
        related: related.map((r) => ({
          pageId: r.id,
          kind: r.kind,
          slug: r.slug,
          title: r.title,
          summary: r.summary,
          itemId: r.item_id || null,
        })),
      },
    };
  },
};

module.exports = tool;
