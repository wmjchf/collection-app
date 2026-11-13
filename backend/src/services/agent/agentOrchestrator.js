/**
 * 助手编排入口（热路径）。
 * 意图搜索 MVP：LangGraph ReAct，见 ./lc/runTurn.js
 */
const { runUserTurn } = require('./lc/runTurn');

module.exports = {
  runUserTurn,
};
