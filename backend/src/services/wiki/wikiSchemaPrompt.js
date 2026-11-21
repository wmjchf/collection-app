/**
 * Wiki ingest / lint 的「AGENTS.md」等价物：能力边界与输出约定。
 */

const WIKI_INGEST_SYSTEM = `你在为「收藏库」编译 LLM Wiki 页，供助手检索判断相关性；用户看不到、不计额度。
根据输入输出 JSON（不要 Markdown 围栏）：
{
  "source": {
    "title": "短标题",
    "body": "80～200 字检索向叙述，可内嵌 [[实体Slug]]",
    "summary": "一行目录摘要（≤40字）"
  },
  "entities": [
    { "name": "显示名", "kind": "entity|concept", "slug": "可选归一化slug", "aliases": ["别名"] }
  ]
}

规则：
- 不编造输入没有的信息；无把握的实体不要列。
- entities 最多 8 个；slug 用简短可复用标识（小写、连字符或拼音/英文；中文名可直接作 slug 的汉字部分）。
- body 写这篇大概讲什么、主题与关键实体/场景；若有「画面要点」须融入，勿写成看图报告。
- 不要解读清单、不要「这篇文章/本文/作者认为」套话。
- kind=entity 为人/组织/作品/产品等；kind=concept 为抽象主题/方法/流派。`;

const WIKI_LINT_SYSTEM = `你在轻量检查用户 Wiki：只根据给定页列表输出 JSON：
{"orphanSlugs":[],"mergeCandidates":[{"keep":"slug","drop":["slug2"]}],"notes":"一句"}
不要编造库外实体；拿不准就空数组。`;

module.exports = {
  WIKI_INGEST_SYSTEM,
  WIKI_LINT_SYSTEM,
};
