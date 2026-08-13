const itemService = require('./itemService');

const pending = new Set();

/**
 * 进程内异步解析队列（第一期）。
 * 后续可换成 Redis / Bull 而不改 API。
 */
function enqueueParse(itemId) {
  const id = Number(itemId);
  if (!id || pending.has(id)) return;

  pending.add(id);
  setImmediate(async () => {
    try {
      await itemService.runContentParse(id);
    } catch (err) {
      console.error(`[parseQueue] item=${id} failed`, err);
    } finally {
      pending.delete(id);
    }
  });
}

module.exports = { enqueueParse };
