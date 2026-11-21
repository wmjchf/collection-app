const agentDigestService = require('./agentDigestService');

const pending = new Set();

function enqueueAgentDigest(itemId) {
  const id = Number(itemId);
  if (!id || pending.has(id)) return;

  pending.add(id);
  setImmediate(async () => {
    try {
      await agentDigestService.runAgentDigestJob(id);
    } catch (err) {
      console.error(`[agentDigestQueue] item=${id} failed`, err);
    } finally {
      pending.delete(id);
    }
  });
}

module.exports = { enqueueAgentDigest };
