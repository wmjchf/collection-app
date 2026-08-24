const itemService = require('./itemService');

const pending = new Set();

/**
 * 进程内转写队列：提交阿里云任务后轮询结果。
 */
function enqueueTranscript(itemId) {
  const id = Number(itemId);
  if (!id || pending.has(id)) return;

  pending.add(id);
  setImmediate(async () => {
    try {
      await itemService.runTranscriptJob(id);
    } catch (err) {
      console.error(`[transcriptQueue] item=${id} failed`, err);
    } finally {
      pending.delete(id);
    }
  });
}

module.exports = { enqueueTranscript };
