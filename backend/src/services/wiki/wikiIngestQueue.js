const wikiIngestService = require('./wikiIngestService');

const pending = new Set();

function enqueueWikiIngest(itemId) {
  const id = Number(itemId);
  if (!id || pending.has(id)) return;

  pending.add(id);
  setImmediate(async () => {
    try {
      await wikiIngestService.runWikiIngestJob(id);
    } catch (err) {
      console.error(`[wikiIngestQueue] item=${id} failed`, err);
    } finally {
      pending.delete(id);
    }
  });
}

module.exports = { enqueueWikiIngest };
