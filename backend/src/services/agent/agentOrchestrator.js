/**
 * 助手编排入口（热路径）。
 * Agentic Search MVP：LangGraph ReAct，见 ./lc/runTurn.js
 */
const { runUserTurn } = require('./lc/runTurn');

module.exports = {
  runUserTurn,
};
