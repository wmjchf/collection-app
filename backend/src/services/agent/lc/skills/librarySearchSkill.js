/**
 * 库内主题检索 Skill：仅在 search 向回合注入 system，避免非检索轮每步重复烧 token。
 */
const LIBRARY_SEARCH_SKILL = `【Skill: 库内检索】
1. search_library / grep_library 只出候选，不进出处。专名用 grep，模糊主题用 search。browse_library_map 可选。
2. 标题/snippet 已能判断相关 → cite_search_hits(itemIds)，不要精读。
3. 拿不准 → get_item_excerpt（点名默认 cite=false；图集默认真图 1～2 张，已看可 peekImages:false）→ 符合再 cite:true。
4. 有收窄（科普/教程等）且标题看不出是否符合 → 须精读严卡，勿硬挂；不符不 cite、不当推荐、不点名落选。
5. 不够则换词再搜；禁止劝用户「说得更具体」代替你换词。
6. 作答格式：先一句交代找到几篇（可写主题），再用 Markdown 无序列表列出已进出处的标题（每项一行，标题可加粗）。禁止多篇挤进同一段、用《》串联。禁止内容梗概、列落选、点评、「想听细节」收尾；用户明确要总结/讲这篇时再展开。
7. 盘点用 list_library，禁止 search/grep「近期收藏」等空词。`;

function formatLibrarySearchSkill() {
  return LIBRARY_SEARCH_SKILL;
}

module.exports = {
  LIBRARY_SEARCH_SKILL,
  formatLibrarySearchSkill,
};
