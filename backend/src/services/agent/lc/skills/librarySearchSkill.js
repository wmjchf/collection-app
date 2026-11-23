/**
 * 库内主题检索 Skill：仅在 search 向回合注入 system，避免非检索轮每步重复烧 token。
 */
const LIBRARY_SEARCH_SKILL = `【Skill: 库内检索】
1. search_library / grep_library 只出候选，不进出处。专名用 grep，模糊主题用 search。browse_library_map 可选。snippet 保持短摘录即可，勿为候选去读全文。
2. 标题/snippet 已能判断**与用户问题直接相关** → cite_search_hits(itemIds)，不要精读。只传最终会在回答里点名的篇；禁止把整页候选一股脑 cite。
3. 拿不准 → get_item_excerpt 点名候选（默认读 Wiki 源页，不读正文/文稿；图集也不看图）→ 符合再 cite:true。无源页时工具会退回短摘录。主题收窄可先 get_wiki_page 读实体/概念页。
4. 有收窄（科普/教程/买手机等意图）且标题看不出 → 用 Wiki 源页/实体页严卡，勿硬挂；不符不 cite、不当推荐、不点名落选。禁止为「确认相关」去读全文。
5. **出处与正文必须一致**：用户可见「出处」= 你 cite 过的篇。不要 cite 后又说「排除/不相关/不算」；要排除就根本不要 cite。正文里点名的每一篇都必须已进出处；出处里的每一篇都必须在正文列表里点名。
6. 用户明确要讲/总结某候选内容时，再 get_item_excerpt 且 preferWikiSource:false（或省略 itemId 读本篇）。
7. 不够则换词再搜；禁止劝用户「说得更具体」代替你换词。
8. 作答格式：先一句交代找到几篇（数字须等于已进出处篇数），再用 Markdown 无序列表**只**列出已进出处的标题（每项一行，标题可加粗）。禁止多篇挤进同一段、用《》串联。禁止内容梗概、列落选、点评「某篇属电脑故排除」、「想听细节」收尾；用户明确要总结/讲这篇时再展开。
9. 盘点用 list_library，禁止 search/grep「近期收藏」等空词。`;

function formatLibrarySearchSkill() {
  return LIBRARY_SEARCH_SKILL;
}

module.exports = {
  LIBRARY_SEARCH_SKILL,
  formatLibrarySearchSkill,
};
