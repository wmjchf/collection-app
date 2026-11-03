const searchLibrary = require('./tools/searchLibrary');
const getItemExcerpt = require('./tools/getItemExcerpt');
const listLibrary = require('./tools/listLibrary');

const ALL_TOOLS = [searchLibrary, getItemExcerpt, listLibrary];

/**
 * @param {{ stages?: string[] }} [opts]
 */
function listTools(opts = {}) {
  const stages = opts.stages || ['P1'];
  const allow = new Set(stages);
  return ALL_TOOLS.filter((t) => allow.has(t.stage));
}

function getTool(name) {
  return ALL_TOOLS.find((t) => t.name === name) || null;
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
