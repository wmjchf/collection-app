const aiMindmapService = require('./aiMindmapService');

const pending = new Set();

function enqueueMindmap(itemId) {
  const id = Number(itemId);
  if (!id || pending.has(id)) return;

  pending.add(id);
  setImmediate(async () => {
    try {
      await aiMindmapService.runMindmapJob(id);
    } catch (err) {
      console.error(`[aiMindmapQueue] item=${id} failed`, err);
    } finally {
      pending.delete(id);
    }
  });
}

module.exports = { enqueueMindmap };
