# 奏折 AI Agent 实现细节

> 状态：**LangGraph 意图搜索 MVP**（库内搜索 + 流式 + 出处；App SSE/UI 不变）  
> 更新日期：2026-11-14  
> 相关：`docs/技术实现.md` §2.6.4b、`docs/付费规划.md`

## 0. 一句话

**AI Agent 是用户级私人 Agent**：当前热路径用 **LangChain.js + LangGraph ReAct** 做库内意图搜索、读篇摘录、生成文稿确认、整理成文章与流式回答；阅读页会预取当前篇。会话 API / SSE 与 App 样式保持兼容。改标、归类等暂未接入。

## 1. 产品定位

| 是 | 不是 |
| --- | --- |
| AI Agent（多轮、可工具调用） | 搜索页的增强模式 |
| 先查库，后整理 / 创作 | 通用联网聊天机器人 |
| 答案默认带出处卡片（可点进阅读） | 无出处的玄学总结 |
| 太子 Pro 卖点能力 | 免费全开 |

**入口（已定稿）**

- 主入口：首页 / 收藏页 AppBar `✦ AI Agent`（与首页「添加」并列；收藏页归类聚焦时让位给新建归类）
- 不进底栏、不进搜索
- 门控：太子+；非会员点入 → 升级页（`from=agent`）

**空态文案口径**

- 构图：居中；主题色 ✦ 圆标（无光晕）+ 标题「你的 AI Agent」+ 副文（空态无能力标）
- 副文：帮你在收藏里更快找到内容，也能深挖原文
- 不展示示例提示卡；输入占位：跟助手说点什么…
- 输入框上方预设：克制短句点选先填入输入框；空会话起步；有回复后按规则切换（标签盘点→整理归类；归类询问→按行业/按主题/由你来分；有出处→深入解读/对照等）；**挂确认条的最后一步不展示预设**，不另调模型

## 2. 目标与非目标

### 2.1 Phase 1（MVP）

1. 多轮对话：用户自然语言 → 检索个人库 → 短答 + 出处卡片（itemId / 标题 / 摘录 / 标签）
2. 点击出处 → 打开阅读页（`openEntry=agent`）
3. 计入太子月 AI token 池；写 `usage_events`
4. 会话可续聊（同一 conversation）；历史列表可后置

### 2.2 能力演进总表（已定）

原则：**创作不与查库同期**；凡创作输出须 anchor 用户库（带 `citations` 或明确选篇），做不到则未到该阶段。

| 阶段 | 能力条 | 做什么 | 不做什么 |
| --- | --- | --- | --- |
| **P1 查** | `查收藏` 点亮 | 检索收藏、对照内容、深挖原文；**改标签 / 归类暂下线**（标签→阅读页；归类→收藏页） | 不静默写库、不批量全库改标、不生成分享稿 |
| **P2 整理** | `整理` 点亮 | 收拢现网 AI 为 Tools：解读 / 脑图 / 打标建议；归类已部分前移至 P1 助手 | 不写对外长文、不发帖 |
| **P3a 轻创作** | `创作` 点亮（轻） | 基于出处的分享文案、对照短评、一句话推荐、摘句润色 | 不写无出处的自由长文 |
| **P3b 中创作** | `创作` 加深 | 多篇综合备忘、主题导读、读书笔记草稿（可编辑再导出） | 不承诺自动发布 |
| **更后 重创作** | — | 大纲 / 脚本 / 对外发布稿 / 自动发帖 | Phase 1～3 明确非目标；质检与版权风险高 |

空态能力条可对未上线项一直灰显引流；点亮顺序必须按上表，不可跳级把「创作」做成通用聊天。

### 2.3 Phase 2（整理：收拢现有 AI）

把下列能力注册为 Tools，**优先复用现有 service**，不重写模型链路：

| Tool | 现有实现 | 说明 |
| --- | --- | --- |
| `summarize_item` | `aiSummaryService` | 解读 / brief |
| `mindmap_item` | `aiMindmapService` | 导图树 |
| `suggest_tags` | `aiSuggestService` | 建议标签（可 `autoApply=false` 给用户确认） |
| `propose_organize`（已落地） | `aiOrganizeService` | 可建议新建架子 + 填入；**确认后** `createModule` / `placeTag` |
| `get_item` / `search_library` | items / search | 查库（Phase 1 核心，P2 继续用） |

阅读页「AI解读」已下线；思维导图暂留「更多」。后续整理 Tools 时可用 `bootstrapTool` 从助手唤起。

### 2.4 Phase 3（创作）

| Tool | 阶段 | 说明 |
| --- | --- | --- |
| **`draft_article`（已落地）** | P3a | **视频转写 → 文章**；`intent=compose`；须成功转写；SSE 真流式 Markdown；口播→书面、禁回指；App「复制全文」；不用正文 |
| **`draft_gallery_article`（已落地）** | P3a | **图集 → 知识向文章**；同 `intent=compose`；VL（默认 `qwen3-vl-plus`）看图；尽量全图（默认最多 24，与向量 6 张上限分开）；流式展示、不写回条目；预设「根据图片整理成文章」 |
| **动态预设（已落地）** | UX | `POST /api/agent/conversations/:id/presets`：按阅读篇/上一轮生成 3～4 条口语预设；**不计用户 AI 额度**；失败回退客户端规则预设 |
| `draft_share_copy` | P3a 预留 | 基于 1～N 个 citation 写分享短文案 / 推荐语 |
| `polish_quote` | P3a 预留 | 摘句润色（不改原意；可附原文对比） |
| `compare_notes` | P3a 预留 | 两篇对照短评（强制两篇 itemId） |
| `draft_memo` | P3b 预留 | 多篇主题备忘 / 导读草稿；返回可编辑正文 + citations |
| `draft_reading_notes` | P3b 预留 | 读书笔记结构稿（论点 / 摘录 / 我的问题） |

重创作（脚本、自动发帖）不进本表，单独立项。

### 2.5 非目标（Phase 1）

- ~~不自动改标签~~ → **助手内改标签暂下线**；阅读页手改；`propose_item_tag_edit` 代码保留；仍不做：无确认静默改标、整篇 AI 重打标流水线、批量全库改标、删条目
- ~~不改归类架子~~ → **助手内归类暂下线**；收藏页手建/拖动；`propose_organize` 代码保留
- 不接外部网页搜索、不读用户未收藏的 URL
- 不做语音输入、不做流式 UI 动画规范以外的花活
- 不在 Phase 1 做跨用户知识、推荐他人内容
- **不做创作**（含分享文案）；能力条「创作 · 即将」仅展示

## 3. 总体架构（当前：LangGraph）

**编排**：`@langchain/langgraph` 的 `createReactAgent`（Thought/tool-call → Observation → Final Answer）。对外仍由 `routes/agent` SSE 映射事件。

```
App 助手页（样式不动）
  │  POST /api/agent/conversations/:id/messages  Accept: text/event-stream
  ▼
agentOrchestrator.js → lc/runTurn.js
  ├─ 门控 / 落 user 消息 / 装配历史
  ├─ buildAgentGraph（lc/graph.js）
  │    ├─ streamTaskPlan → SSE thinking（任务理解与规划口语）
  │    ├─ 规划正文注入 ReAct system（约束执行优先按规划调 tool）
  │    ├─ ChatOpenAI → 百炼 + Tools：search_library / list_library / get_item_excerpt / generate_transcript / draft_article
  ├─ streamEvents → SSE phase / token；thinking 落库 `tool_calls_json.thinking`
  ├─ citations[] ← 工具命中（落库最多 12；气泡默认露 3，「加载更多」展开）；generate_transcript 可挂 pendingAction；draft_article 真流式成文
  └─ usageService.recordAiTokenUsage（feature=agent）
```

**原则**

1. **Thin runTurn, fat tools**：检索逻辑仍在原 `search_library`；编排只负责 ReAct + SSE
2. **出处来自工具**：`citationMap` 只收录工具返回；禁止模型编造 itemId
3. **App 契约稳**：`thinking` / `phase` / `token` / `user` / `done` / `error` 字段与旧版兼容；文稿确认条仍走 `pendingAction`
4. **加能力**：以 `lc/tools/*` 包装原 service；勿再堆 intent 分支大文件
5. **生成文稿不在 ReAct 内跑 ASR**：Tool 只校验并挂确认；App 确认后提交并 `settle-transcript`
6. **先规划后执行**：规划与 ReAct 串行；规划文本注入执行 prompt，避免「想的一套、做的一套」
7. **成文在 Tool 内流式**：`draft_article` 直接 `token`；抑制模型事后复述

### 3.1 框架策略（已定 · 2026-11-14）

**结论：热路径已换为 LangChain.js + LangGraph；API / 会话 / 计费 / 检索服务保持自研。**

#### 分层（硬边界）

| 层 | 职责 | 演进时怎么动 |
| --- | --- | --- |
| **API / 会话** | `routes/agent`、conversations/messages、SSE | 对外契约尽量稳；App 只依赖此层 |
| **Orchestrator（lc/）** | LangGraph ReAct + SSE 映射 + 落库 | 加能力时加 Tool / 改 prompt，避免再堆 intent 分支 |
| **Policy** | 出处条数、检索 limit、额度门控 | 规则仍集中在 `agentPolicy` / `usageService` |
| **Tools** | LangChain Tool 包装现有 execute | 新能力：`lc/tools/*` 调原 service |
| **Providers** | `lc/model.js`（ChatOpenAI→百炼）；embedding 仍 `aliyunDashScope` | 换供应商优先动 model 层 |
| **Memory** | `listRecentHistory` → Human/AIMessage | 后期可加摘要压缩 |
| **计量** | `usage_events` feature=agent | 从 LC usage_metadata 合并记账 |

#### Tool 注册契约（扩展点）

每个 tool 必须可被静态列出（供模型 schema + 单测）：

```js
// 示意
{
  name: 'search_library',
  stage: 'P1',                    // 能力阶段，便于按 flag 开关
  mutates: false,                 // true 则只能返回 pendingAction
  schema: { /* JSON Schema for args */ },
  execute: async (ctx, args) => ({ ok, data, citations? })
}
```

- `ctx`：`{ userId, conversationId, messageId, signal }` — 禁止 tool 自己读「别的用户」
- 返回值进 Observation；`citations` 由编排器合并进最终消息（tool 可贡献，Answer 不可瞎编）
- Phase 开关：`AGENT_TOOLS_ENABLED=search_library,get_item_excerpt,generate_transcript` 这类白名单，未到阶段的 tool 不进 schema

#### 何时考虑引入框架（换 Orchestrator，不推倒 Tools）

同时满足再评估（大约 P2 末～P3，而非现在）：

1. 出现 **多分支 / 并行多工具 / 人机多轮打断** 的持久化执行图，自研循环明显难维护  
2. 团队愿意承担框架升级与调试成本  
3. Tools / Policy / API **已经稳定**，迁移只是把 while-ReAct 换成图节点  

迁移目标：新编排调用同一 `toolRegistry.execute`；会话表与 App API **不改或仅加字段**。

#### 意图路由（硬约定，2026-11-06）

- **自然语言意图只认 plan JSON**（`intent` / `queries` / `excerptItemIds` / `listContinue` / `tagEdit` / `organize`），编排按计划调工具  
- **禁止**用口令正则覆盖 / 强改 intent（盘点、改标、归类、类似文章等一律由模型选 intent）  
- 阅读页 `focusBound`：仅当 plan **未给 queries** 且未走 list/对照/改标/归类时，才钉当前篇；有检索词即查库并排除本篇  
- `normalizePlan` 只做校验与缺省补全（出处 ID 白名单、tagEdit.itemId、compare 缺篇、勾选标题）  
- 可残留：确认条 / 口头「可以」确认写库、助手气泡结构识别（是否已问过分法）；**不得**再为新口令加 `looksLike*` 改 intent  

#### 反模式（禁止）

- 用正则表穷举用户说法来改 intent / 清空 queries  
- 在 prompt 里堆业务 if-else，却不进 Policy  
- Tool 内直接 `res.json` / 改 HTTP；或 Orchestrator 内直接改 `item_tags`  
- 为「以后可能用」提前引入 LangGraph 空壳依赖  
- 一个 PR 里同时加 3 个以上新 tool 且无 trace / 单测  

## 4. 数据模型

新建迁移建议：`0xx_agent_conversations.sql`。

### 4.1 `agent_conversations`

| 列 | 类型 | 说明 |
| --- | --- | --- |
| `id` | BIGINT PK | |
| `user_id` | BIGINT | 索引 |
| `title` | VARCHAR(128) NULL | 可由首条用户消息截断生成 |
| `focus_item_id` | BIGINT NULL | NULL=全局助手；非空=阅读页该篇专属会话 |
| `status` | ENUM/`active`/`archived` | 默认 active |
| `created_at` / `updated_at` | DATETIME | |

### 4.2 `agent_messages`

| 列 | 类型 | 说明 |
| --- | --- | --- |
| `id` | BIGINT PK | |
| `conversation_id` | BIGINT | 索引 |
| `role` | `user` / `assistant` / `tool` / `system` | |
| `content` | MEDIUMTEXT | 对用户可见的文本；tool 角色可存 JSON 字符串 |
| `citations_json` | JSON NULL | `[{ itemId, title, snippet, tagNames[] }]` |
| `tool_calls_json` | JSON NULL | 本轮规划出的 tool calls |
| `usage_event_id` | BIGINT NULL | 关联计量（可选） |
| `created_at` | DATETIME | |

### 4.3 （可选）`agent_tool_runs`

长任务（总结 / 脑图）与现网 queue 对齐时用：

| 列 | 说明 |
| --- | --- |
| `id` / `message_id` / `tool` / `item_id` | |
| `status` | `queued` / `running` / `succeeded` / `failed` |
| `result_ref` | 如指向 `ai_meta.summary` 或 ephemeral id |
| `error_code` / `error_message` | |

Phase 1 若只做同步检索 + 一次合成，可先不建此表，tool 结果内联进 `tool` message。

## 5. API

均需登录；太子+（`features.aiAgent` 或复用 `aiSummary` 门控，建议 **独立 feature flag `ai_agent`**，便于灰度）。

### 5.1 会话

```
POST /api/agent/conversations
Body: { title?, focusItemId? }
→ { id, title, focusItemId }

POST /api/agent/conversations/ensure
Body: { focusItemId?, title? }   // 无 focus → 全局；有 → 该篇专属（没有则建）
→ { id, title, focusItemId }

GET /api/agent/conversations?limit&cursor&focusItemId&global=1
→ { items: [{ id, title, focusItemId, updatedAt, preview }] }

GET /api/agent/conversations/:id
→ { id, title, messages: [...] }

DELETE /api/agent/conversations/:id
→ 归档或硬删（产品定；建议归档）
```

### 5.2 发消息（Phase 1 推荐：同步短链路 + 可选 stream）

```
POST /api/agent/conversations/:id/messages
Body: {
  content: string,          // 用户话
  clientMessageId?: string, // 幂等
  focusItemId?: number      // 阅读页锚定：强制 get_item_excerpt 该篇
}

→ 202 + { assistantMessageId, status: 'running' }   // 若走队列
或 200 + AssistantMessagePayload                   // 检索够快可同步
```

**AssistantMessagePayload**

```json
{
  "id": "…",
  "role": "assistant",
  "content": "你库里至少有两篇…",
  "citations": [
    {
      "itemId": 123,
      "title": "慢变量：复利之外的耐心",
      "snippet": "「真正拉开差距的…」",
      "tagNames": ["长期主义", "复利"],
      "coverImageUrl": "…"
    }
  ],
  "toolTrace": [
    { "tool": "search_library", "args": { "q": "长期主义" }, "ok": true }
  ],
  "usage": { "tokensBilled": 1234 }
}
```

轮询（若 202）：

```
GET /api/agent/messages/:id
→ { status, message? , error? }
```

Stream（已落地）：`Accept: text/event-stream`，事件 `user` / `phase`（planning|searching|answering）/ `token` / `done`（含完整 assistant + citations）/ `error`。plan+工具仍同步；仅 answer 纯文本流式。

### 5.3 确认类写操作（改标签 / 归类：工具保留，助手入口暂下线）

```
POST /api/agent/actions/confirm
Body: { conversationId, messageId, approve: true|false }
```

从该助手消息的 `pendingAction`（写入 `tool_calls_json`）读取预览：

- `item_tag_edit`：`approve` → `setItemTags`
- `organize_tags`：`approve` → `applyOrganize`（可 `createModule` + `placeTag`）

`approve=false` 标记取消。已确认/已取消幂等。

### 5.3b 步骤态 `awaiting`（防串题）

助手消息 `tool_calls_json.awaiting` 标明「正在等用户哪一步」：

| 值 | 何时挂上 | 下一轮 |
| --- | --- | --- |
| `organize_preference` | 归类询问「怎么分」 | 仅明确分法/取消继续；对照/检索等换题放行 |
| `tag_edit_preference` | 只说改标签、未给加删 | 列出当前标签并询问；未换题钉住 `tag_edit`，加删由 plan 理解任意说法后出带按钮预览 |
| `organize_confirm` / `tag_edit_confirm` | 挂 `pendingAction` 时 | **仅此时 App 出确认按钮**；改标确认态未换题仍钉 `tag_edit`（换建议/同意由模型理解）；禁止正文手写「请确认是否写入」 |

实现：`agentAwaiting.js`（`resolveAwaiting` / `looksLikeTopicSwitch` / `shouldContinueAwaiting`）。后续新半成品对话加一种 awaiting 值即可，避免两两特判。

**对照选篇**：意图为 `compare` 但未勾选满两篇、且非「这/刚才两篇」等明确回指时，系统固定提示勾选出处（不挂 awaiting、不用上文静默凑篇）。

## 6. Tools 规格

### 6.1 Phase 1

#### `search_library`

| 项 | 说明 |
| --- | --- |
| Args | `{ q: string, tagNames?: string[], limit?: number }` |
| 实现 | 复用现网全文/标签搜索（`GET /api/items/search` 同源逻辑）；只搜当前 `user_id` |
| 返回 | `{ hits: [{ itemId, title, snippet, score?, tagNames[] }] }` |
| 限制 | `limit` 默认 6、硬顶 12；snippet 优先命中句，否则标题/摘要截断 |

#### `get_item_excerpt`

| 项 | 说明 |
| --- | --- |
| Args | `{ itemId, maxChars?: number }` |
| 实现 | `aiInput.buildInputText` 后按 `maxChars`（默认 6k～12k）截断；音视频无文稿时摘录可能为空，可再调 `generate_transcript` |
| 返回 | `{ title, excerpt, tagNames, contentHash }` |

#### `generate_transcript`

| 项 | 说明 |
| --- | --- |
| Args | `{ itemId?, thenCompose? }`；`itemId` 省略则用当前阅读篇 |
| 实现 | 校验属主与可转写媒体；**不**调用 `requestTranscript`、不扣分钟 |
| 返回 | `ready` / `running` / `needs_confirm` / `no_media` / `missing_item` 等 JSON |
| 确认 | `needs_confirm` 时写入 `pendingAction` + 后端确认文案（含剩余分钟）；抑制模型口头答复 token；App 只做档位门控与「开始生成」 |
| 结算 | App 完成后 `POST /api/agent/actions/settle-transcript` 写回 status / content |
| 成文 | `thenCompose=true` 时确认成功后 App 续发「整理成一篇文章」→ `draft_article` |

#### `draft_article`

| 项 | 说明 |
| --- | --- |
| Args | `{ itemId? }`；省略则当前阅读篇 |
| 视频 | 复用 `draftFromTranscript`；须成功文稿；口播→书面 Markdown 流式 |
| 图集 | 复用 `draftFromGallery`；VL 看图（`ALIYUN_AI_MODEL_AGENT_VISION`）；知识向成文 / 生活向短拒 |
| 无文稿 | 返回 `need_transcript`，模型应改调 `generate_transcript(thenCompose=true)` |
| 流式 | Tool 内 `chatTextStream` → SSE `token`；`runtime.draftContent` 落库；不写回条目 |

#### `propose_item_tag_edit`（只读预览）

| 项 | 说明 |
| --- | --- |
| Args | `{ itemId, add?: string[], remove?: string[], replace?: string[] }` |
| 实现 | 校验属主；`listItemTags` 算 before/after/willCreate；**不写库** |
| 返回 | `{ title, before, after, add, remove, willCreate, noop }` + citations |
| 写入 | 用户点确认 → `POST /api/agent/actions/confirm` → find-or-create + `setItemTags` |

#### `propose_organize`（只读预览）

| 项 | 说明 |
| --- | --- |
| Args | `{ hint?: string, mode?: 'ungrouped'\|'full' }` |
| 实现 | `suggestOrganize`（可建议新建归类）；**不写库**；hint 上限 700 |
| 返回 | `modules`（含 `create`）/`willCreateModules`/`ungroupedTagIds` |
| 写入 | 确认 → `applyOrganize` |
| 短回复 | 「新建一个」等：编排层 `buildOrganizeHint` 把上文助手建议拼进 hint，避免丢掉点名标签 |
| 口头确认 | 「可以/确认」→ 执行 pending 或按上文方案 `applyOrganize`；禁止只回「已确认执行」不写库 |
| 归类三步 | 查标签 → 未带分法才问意见 → 有明确意见或表态后 `propose_organize` 确认条写入 |
| 盘点标签 | **暂下线**：问全库标签时引导收藏页；`list_tags` 工具代码保留 |
| 改单篇标签 | **暂下线写入**：引导阅读页手改；`propose_item_tag_edit` 工具代码保留 |
| 推荐标签 | **只读**：走普通 search+本篇摘录→回答 LLM；不写库、无专用 turn |

#### `answer`（内部，非 LLM tool）

编排层根据 tool 结果生成对用户短答；prompt 约束：

- 只依据工具返回的内容，禁止编造库外事实
- 提及具体篇目时必须能在 `citations` 找到对应 `itemId`
- 找不到时直说，并建议换说法或去搜索页用关键词
- `tag_edit`：**暂下线**；引导阅读页手改标签，勿出预览确认条

### 6.2 Phase 2 Tools（包装现网）

每个 tool 调用路径：

1. Orchestrator 解析出 `itemId`（来自用户指定或上一轮 citation）
2. 调用现有 `requestSummary` / `requestMindmap` / …（含门控、queue、转写互斥）
3. 若异步：写入 `agent_tool_runs`，助手消息先回「正在生成解读…」，完成后补一条 assistant 或 patch 原消息
4. 计量：仍走各 service 现有 `usage_events`；Agent 编排本身的规划 token **另计或合并进同池**（建议合并，事件类型 `ai_agent`）

**`propose_organize`**：只返回预览 JSON；`confirm` 后调 `applyOrganize`（可新建架子）。

## 7. 编排与模型（ReAct）

### 7.1 循环约定

| 项 | 约定 |
| --- | --- |
| 一步 | `Thought`（可选展示）→ `Action{tool, args}` → `Observation` |
| 结束 | 模型产出 `Final Answer`，或编排器判定「已有足够 citations / 明确未找到」 |
| 步数上限 | Phase 1 建议 **≤ 4**（典型：search → excerpt×1～2 → answer）；超出强制收束并说明 |
| 同工具重复 | 相同 `tool+args` 连续两次 → 打断，要求换策略或直接回答 |
| 异步工具（P2） | Action 返回 `pending`；对用户先发「进行中」消息；完成后再入一轮 Observation → Answer |
| Trace | `toolTrace[]` 必存（可对用户折叠）；便于排障与用量拆分 |

### 7.2 模型与上下文

| 项 | 建议 |
| --- | --- |
| 规划模型 | `ALIYUN_AI_MODEL_AGENT`（与遗留 `ALIYUN_AI_MODEL_TAGS` **独立**；默认 `qwen3.8-flash`，可单独升 27b/max） |
| 实现形态 | 优先 **原生 tool-calling**（Thought 隐式/显式均可）；无可靠 tool-call 时再退回文本 ReAct 解析 |
| 单篇重活 | 打标/收藏页归类用 `ALIYUN_AI_MODEL_TAGS`；脑图用 `ALIYUN_AI_MODEL`；深挖解读走助手同一 `ALIYUN_AI_MODEL_AGENT` |
| Context | 近期 N 轮消息 + 本轮 Thought/Action/Observation；单篇正文仍走 `aiInput` cache_control，避免全文进历史 |
| System prompt | 身份=奏折 AI Agent；ReAct 规则；能力边界；禁止越权写库；中文；必须 citations |

### 7.3 Phase 1 可先「浅 ReAct」

固定骨架：`search_library`（必要时再 `get_item_excerpt`）→ 一次 Final Answer。  
仍走同一 orchestrator 与消息/trace 形状，便于 P1.1 打开完整多步 ReAct，而不改 API。

## 8. 额度与门控

| 项 | 说明 |
| --- | --- |
| 档位 | 太子+（与解读同级） |
| 计量 | `(prompt - cached) + completion`；事件 `type=ai_agent`（规划+回答）；tool 内总结/脑图继续各自 type 或统一归 `ai_agent` 子字段 `tool` |
| 自动打标 | **已下线**（`maybeAutoTag*` no-op；不走 Agent） |
| 触顶 | 402 + 升级引导；助手页展示本月剩余与现网 usage 一致 |
| 配置 | `USAGE_ENFORCING`；`features.aiAgent` |

`usageService` / App `UsagePlan` 增加 `aiAgent: hasPrince`；升级页权益文案加「AI Agent」。

## 9. App 实现要点

### 9.1 路由与入口

- `HomePage` AppBar `actions`：在添加按钮左侧加 `助手` chip（视觉对齐 Figma）
- `AgentPage`（或 `AssistantPage`）：空态 / 线程 / 输入框；出处用接近 `ItemListTile` 的卡片；划选消息出阅读页同款工具条（复制 / 分享）
- 埋点：`agent_open` / `agent_send` / `agent_citation_open` / `agent_upgrade_gate`

### 9.2 状态

- 本地：当前 `conversationId`、消息列表、sending/streaming；**会话消息 SharedPreferences 缓存**（按用户 + 全局/篇），进页先渲染缓存再 `ensure`+拉网同步
- 出处点击 → `ItemReadingPage(openEntry: 'agent')`；左侧勾选 → 输入胶囊内蓝底标题 chip（可 × 取消），发送时拼「标题」锁定篇目
- 阅读页底栏首位「AI Agent」→ `openAgent(focusItemId)` 篇专属会话；首页/收藏/侧栏 → 全局会话。手机全屏 `AgentPage`；iPad：三列从列表右缘顶入（挤没侧栏+列表），两列枢纽压一半（`AgentSplitInset` / `asPanel`）
- 盘点类问题（有哪些/有多少收藏）→ `list_library`，勿用空泛词 `search_library`
- 带时间的盘点（今天/昨天/本周/本月/最近收藏）→ `list_library` + `scope`（服务端 `resolveListScope` 算 Asia/Shanghai 时间窗）；回答不得把窗外旧篇说成该时段的；对话内不续翻
- 「最近阅读 / 朕已阅」「批注 / 朱批」盘点 → `list_library` + `scope=recent_read|annotated`（与收藏页瓷砖同一套 `systemFilterService` 规则：近 7 天已读 / 有标注）；最多 3 条样例，完整列表在库外浏览
- 「还有吗 / 再列其他」→ 不再对话内翻页，提示去首页/收藏页，或说主题做意图搜索
- 错误：额度 / 网络 / 空库；空库引导去添加链接

### 9.3 与阅读页 AI 的关系（演进）

| 阶段 | 行为 |
| --- | --- |
| P1 | 阅读页去掉独立「AI解读」；解读/深挖走助手（阅读锚定 + 追问）；底栏 助手/标签/感想/更多（脑图、转写） |
| P2 | 脑图等可「在助手中打开」；底层同一 service；`summarize_item` Tool 可选接回 |
| P3 | 底栏入口改为唤起助手并带 `bootstrap: { tool, itemId }`；sheet UI 可删或变薄 |

## 10. 检索质量（Phase 1 → 知识库）

1. **plan 按意图改写检索词**：`queries` 不是从用户原话抠词，而是理解要找什么后产出 1～2 个短主题/同义词；回答仍只能基于命中，不得编库外篇目  
2. **召回层（已落地）**：`item_embeddings` + DashScope embedding；`search_library` **语义优先，关键词 LIKE 兜底**；有强关键词命中时仍丢掉仅正文顺带提到的弱命中；盘点类走 `list_library`  
3. **索引时机**：解析成功、用户改正文后异步 `scheduleIndexItem`；**使用指引（`platform=guide`）永不入库**；删条目靠 FK CASCADE；存量 `pnpm kb:index`；`AGENT_KB_ENABLED=false` 可关  
4. **阅读页找类似**：明确查库时 `excludeItemIds` 排除当前篇，避免本篇占满名额  
5. **聊天不是搜索结果页**：正文点最贴几条；出处卡默认 **3**，本轮池最多 **12**，「加载更多」展开（不再次搜库）；命中仍多时可提醒意图说得更具体  
6. 用户问「对照 A 和 B」：识别两篇 → 两篇 excerpt → 对比段落  
7. 编排仍自研薄 ReAct；**不上整包 LangChain**；向量存储可后续从 MySQL JSON 近邻换 pgvector/Qdrant，只动 retrieval  
8. snippet：语义命中用 chunk 摘要；关键词命中优先含 query 的句子；禁止整篇塞进 citations UI  

## 11. 安全与隐私

- 严格 `user_id` 隔离；tool 层所有 item 查询带 owner 校验  
- Prompt 注入：工具结果当数据，不当指令；用户消息不直接拼进 system  
- 不把 API Key、内部 prompt 全文打进客户端  
- 会话内容属用户数据，删除账号时级联删 `agent_*`  

## 12. 分阶段交付

| 阶段 | 交付 | 验收 |
| --- | --- | --- |
| P0 设计 | Figma + 本文 | 入口与空态/查库屏对齐 |
| **P1.0 查** | 会话 API + `search_library` + 短答出处 + 首页入口 + 门控 | 太子可问「我存过哪些…」并点进阅读；免费被拦；能力条仅「查收藏」亮 |
| **P1.1 查** | 多轮上下文（上文 citations → `excerptItemIds`）、历史列表、可选 SSE | 追问「第二篇呢 / 对比这两篇」不丢语境、不另起无关检索 |
| **P1.2 改标** | `propose_item_tag_edit` + `POST /api/agent/actions/confirm`；App 确认条 | 点名/当前篇「用某某标签」出预览，确认后 `setItemTags`；取消不写库 |
| **P1.3 归类** | `propose_organize`（可新建架子）+ confirm；收藏页去掉 AI 入口 | 「帮我建归类/填入」出预览，确认后 `createModule`/`placeTag` |
| **P2.0 整理** | Tools：summary / mindmap；阅读页可跳转助手 | 助手内生成解读并写入 `ai_meta`；能力条「整理」亮 |
| **P2.1 整理** | Tools：suggest_tags / organize（确认条） | 无静默改库；点名改标已在 P1.2 |
| **P3a 轻创作** | `draft_share_copy` / `polish_quote` / `compare_notes` | 输出必带 citations；能力条「创作」亮 |
| **P3b 中创作** | `draft_memo` / `draft_reading_notes` | 多篇选篇 UX + 可编辑草稿；仍可点回出处 |
| 更后 | 重创作（大纲/脚本/发布） | 单独立项，不在本里程碑内 |

## 13. 目录与代码落点（建议）

**Backend**（按 §3.1 分层；Orchestrator 可整目录替换）

```
services/agent/
  agentOrchestrator.js       # 仅 ReAct 循环（可替换层）
  agentPolicy.js             # 步数 / citations / mutates 确认
  agentPrompt.js             # system + 阶段说明
  agentConversationService.js
  agentRegistry.js           # 注册表：按 stage/flag 露出 tools
  tools/
    searchLibrary.js
    getItemExcerpt.js
    summarizeItem.js         # P2
    mindmapItem.js           # P2
    …
routes/agent.js              # /api/agent
```

复用：`aiInput.js`、`aliyunDashScope.js`、`usageService.js`、现有 `ai*Service`。  
单测优先：`agentPolicy` + 各 `tools/*`（mock service）；编排用少量集成测即可。

**App**

- `features/agent/agent_page.dart`
- `features/agent/agent_repository.dart`
- `features/agent/widgets/citation_card.dart`
- `home_page.dart` / `collection_page.dart` 入口

## 14. 开放问题

1. 会话历史是否进「账户」二级页，还是助手页内抽屉即可？  
2. Phase 1 无文稿时是否允许助手代开转写（会吃转写分钟）？  
3. 编排 token 与 tool 内 token 是否在用量页拆开展示？  
4. 整理/创作能力条是否对非太子可见（灰态引流）？建议可见、点击进升级。  

## 15. 与现网文档同步清单（实现时勾）

- [x] `docs/技术实现.md` 新增 §2.6.x AI Agent  
- [x] `docs/付费规划.md` 权益表加「AI Agent」  
- [x] `docs/DB-SCHEMA.md` 表结构  
- [x] App Store / 升级页 / 协议文案（上线前）  
- [ ] 埋点白名单 `agent_*`  
