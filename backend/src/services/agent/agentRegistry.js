const searchLibrary = require('./tools/searchLibrary');
const getItemExcerpt = require('./tools/getItemExcerpt');
const listLibrary = require('./tools/listLibrary');
const listTags = require('./tools/listTags');
const proposeItemTagEdit = require('./tools/proposeItemTagEdit');
const proposeOrganize = require('./tools/proposeOrganize');
const draftFromTranscript = require('./tools/draftFromTranscript');
const draftFromGallery = require('./tools/draftFromGallery');

const ALL_TOOLS = [
  searchLibrary,
  getItemExcerpt,
  listLibrary,
  listTags,
  proposeItemTagEdit,
  proposeOrganize,
  draftFromTranscript,
  draftFromGallery,
];

/**
 * @param {{ stages?: string[] }} [opts]
 */
function listTools(opts = {}) {
  const stages = opts.stages || ['P1'];
  const allow = new Set(stages);
  return ALL_TOOLS.filter((t) => allow.has(t.stage));
}

function getTool(name) {
  const key = String(name || '');
  // 旧名兼容：draft_from_transcript → draft_article
  if (key === 'draft_from_transcript') {
    return ALL_TOOLS.find((t) => t.name === 'draft_article') || null;
  }
  return ALL_TOOLS.find((t) => t.name === key) || null;
}

async function executeTool(name, ctx, args) {
  const tool = getTool(name);
  if (!tool) {
    return { ok: false, error: `unknown_tool:${name}` };
  }
  if (tool.mutates) {
    return {
      ok: false,
      error: 'mutates_requires_confirm',
      pendingAction: { tool: name, args },
    };
  }
  return tool.execute(ctx, args || {});
}

module.exports = {
  listTools,
  getTool,
  executeTool,
};
