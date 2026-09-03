const aiSummaryService = require('./aiSummaryService');

const pending = new Set();

function enqueueSummary(itemId) {
  const id = Number(itemId);
  if (!id || pending.has(id)) return;

  pending.add(id);
  setImmediate(async () => {
    try {
      await aiSummaryService.runSummaryJob(id);
    } catch (err) {
      console.error(`[aiSummaryQueue] item=${id} failed`, err);
    } finally {
      pending.delete(id);
    }
  });
}

module.exports = { enqueueSummary };
