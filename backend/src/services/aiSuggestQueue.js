const aiSuggestService = require('./aiSuggestService');

const pending = new Set();

function enqueueAiSuggest(itemId) {
  const id = Number(itemId);
  if (!id || pending.has(id)) return;

  pending.add(id);
  setImmediate(async () => {
    try {
      await aiSuggestService.runAiSuggestJob(id);
    } catch (err) {
      console.error(`[aiSuggestQueue] item=${id} failed`, err);
    } finally {
      pending.delete(id);
    }
  });
}

module.exports = { enqueueAiSuggest };
