# 奏折私人助手（AI Agent）实现细节

> 状态：P1.0 已落地（查库 + 出处 + 首页入口）；本文继续作为演进规格  
> 更新日期：2026-11-03  
> 相关：`docs/技术实现.md` §2.6、`docs/付费规划.md`、Figma `奏折 · 问收藏 AI`

## 0. 一句话

**助手是用户级私人 Agent**：对话入口在阅读页右上角。能力顺序固定为 **查 → 整理 → 轻创作 → 中创作**（重创作更后）；创作必须能点回出处。现网解读 / 脑图 / 归类等收成 **Agent Tools**，阅读页独立 AI 入口逐步降级为「打开助手并预填任务」。

## 1. 产品定位

| 是 | 不是 |
| --- | --- |
| 私人助手 / Agent（多轮、可工具调用） | 搜索页的增强模式 |
| 先查库，后整理 / 创作 | 通用联网聊天机器人 |
| 答案默认带出处卡片（可点进阅读） | 无出处的玄学总结 |
| 太子 Pro 卖点能力 | 免费全开 |

**入口（已定稿）**

- 主入口：阅读页 AppBar 右上角 `✦ 助手`（与「添加」并列）
- 不进底栏、不进搜索
- 门控：太子+；非会员点入 → 升级页（`from=agent`）

**空态文案口径**

- 构图：居中；暗绿光核 ✦ + 标题「你的私人助手」+ 副文 + 能力标（检索内容 / 对照内容 / 深挖原文）
- 副文：帮你在收藏里更快找到内容，也能深挖原文
- 不展示示例提示卡；输入占位：跟助手说点什么…

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
| **P1 查** | `查收藏` 点亮 | 检索收藏、对照内容、深挖原文（围绕已找到篇目追问观点/原话） | 不写库、不生成分享稿 |
| **P2 整理** | `整理` 点亮 | 收拢现网 AI 为 Tools：解读 / 脑图 / 打标建议 / 归类预览（确认后写入） | 不写对外长文、不发帖 |
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
| `organize_tags` | `aiOrganizeService` | 归类预览；**必须确认后 apply** |
| `get_item` / `search_library` | items / search | 查库（Phase 1 核心，P2 继续用） |

阅读页底栏「AI解读 / 思维导图」可保留为快捷入口：等价于打开助手并带 `bootstrapTool`。

### 2.4 Phase 3（创作）Tools 预留

| Tool（暂定） | 阶段 | 说明 |
| --- | --- | --- |
| `draft_share_copy` | P3a | 基于 1～N 个 citation 写分享短文案 / 推荐语 |
| `polish_quote` | P3a | 摘句润色（不改原意；可附原文对比） |
| `compare_notes` | P3a | 两篇对照短评（强制两篇 itemId） |
| `draft_memo` | P3b | 多篇主题备忘 / 导读草稿；返回可编辑正文 + citations |
| `draft_reading_notes` | P3b | 读书笔记结构稿（论点 / 摘录 / 我的问题） |

重创作（脚本、发布稿、自动发帖）不进本表，单独立项。

### 2.5 非目标（Phase 1）

- 不自动改标签 / 归类 / 删内容（无确认写操作）
- 不接外部网页搜索、不读用户未收藏的 URL
- 不做语音输入、不做流式 UI 动画规范以外的花活
- 不在 Phase 1 做跨用户知识、推荐他人内容
- **不做创作**（含分享文案）；能力条「创作 · 即将」仅展示

## 3. 总体架构

**编排默认采用 ReAct（Reason + Act）**：Thought → Action(tool) → Observation → … → Final Answer（短答 + citations）。不是「一次生成聊天气泡」，中间必须能落在可执行工具与可核对观察上。

```
App 助手页
  │  POST /api/agent/conversations
  │  POST /api/agent/conversations/:id/messages  (stream 或 job+poll)
  ▼
agentOrchestrator（ReAct loop）
  ├─ Thought：本步意图（可对用户折叠，trace 必留）
  ├─ Action  → toolRouter
  │    ├─ search_library      → itemService.search / tags.search
  │    ├─ get_item_excerpt    → aiInput.buildInputText（截断策略）
  │    ├─ summarize_item      → aiSummaryService   【P2】
  │    ├─ mindmap_item        → aiMindmapService   【P2】
  │    ├─ suggest_tags        → aiSuggestService   【P2】
  │    └─ organize_preview    → aiOrganizeService  【P2】
  ├─ Observation：工具 JSON 写回上下文（不当成 system 指令）
  ├─ 循环直至 Final Answer 或触顶（见 §7）
  ├─ answerComposer（短答 + citations[]）
  └─ usageService.recordAiTokens（与现网同池）
```

**原则**

1. **ReAct + Thin orchestrator, fat tools**：业务规则仍在原 service（门控、转写互斥、contentHash 缓存、`awaitTranscript`）
2. **写操作二次确认**：归类 / 打标应用 / 删除类工具只返回 preview；App 出确认条再调 apply API
3. **出处强制**：凡引用库内内容，响应必须带 `citations[]`（可空数组 + 明确「库里没找到」）；Final Answer 不得引用 Observation 里没有的 itemId
4. **与单篇 AI 共存**：`items.ai_meta` 继续存单篇产物；Agent 会话存对话与工具轨迹，不把长文解读只塞进 chat message
5. **Observation 当数据**：工具返回只作事实；防 prompt 注入（用户/工具文本不升级为系统指令）
6. **可替换编排、不可替换边界**：复杂度涨在 Tools / Policy；Orchestrator 保持可整体替换（见 §3.1）

### 3.1 可扩展性与框架策略（已定）

**结论：P1～P2 自研薄 ReAct，不上 LangChain / LangGraph 等重框架；但按「以后只换编排层」分层，避免编排与业务缠死。**

复杂度会随能力变多而涨，主要涨在 **工具与产品规则**，不在「有没有框架」。框架也消不掉：出处校验、写库确认、额度、转写互斥、`user_id` 隔离——这些必须落在自家 Policy / Tools。

#### 分层（硬边界）

| 层 | 职责 | 演进时怎么动 |
| --- | --- | --- |
| **API / 会话** | `routes/agent`、conversations/messages、SSE/轮询 | 对外契约尽量稳；App 只依赖此层 |
| **Orchestrator** | 只跑 ReAct 循环：调模型 → 解析 tool call → 等 Observation → 收束 | **允许整文件替换**为 LangGraph 等；禁止内联业务 SQL / 改标签逻辑 |
| **Policy** | 步数上限、同工具去重、citations 校验、写操作必须 pendingConfirm、门控/触顶文案码 | 规则集中；新增能力先加 policy，不改循环骨架 |
| **Tools（注册表）** | 统一 `{ name, schema, execute(ctx, args) }`；内部调现有 `ai*Service` / search | **只加新 tool 文件**，不改 orchestrator |
| **Providers** | DashScope chat / tool-calling 封装（可继续放 `aliyunDashScope.js`） | 换模型供应商时只动此层 |
| **Memory** | 近期消息装配、摘要压缩（后期）、勿把全文塞进历史 | P1.1+；与编排解耦 |
| **Runs / 计量** | `agent_tool_runs`、异步工具、`usage_events` | 长任务与编排循环分离 |

```
新增「创作」能力时的正确姿势：
  ✅ tools/draftShareCopy.js + policy 要求 citations
  ❌ 在 orchestrator 里写 if (intent === 'create') { ... 大段逻辑 }
```

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
- Phase 开关：`AGENT_TOOLS_ENABLED=search_library,get_item_excerpt` 这类白名单，未到阶段的 tool 不进 schema

#### 何时考虑引入框架（换 Orchestrator，不推倒 Tools）

同时满足再评估（大约 P2 末～P3，而非现在）：

1. 出现 **多分支 / 并行多工具 / 人机多轮打断** 的持久化执行图，自研循环明显难维护  
2. 团队愿意承担框架升级与调试成本  
3. Tools / Policy / API **已经稳定**，迁移只是把 while-ReAct 换成图节点  

迁移目标：新编排调用同一 `toolRegistry.execute`；会话表与 App API **不改或仅加字段**。

#### 反模式（禁止）

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
→ { id, title }

GET /api/agent/conversations?limit&cursor
→ { items: [{ id, title, updatedAt, preview }] }

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
  clientMessageId?: string  // 幂等
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

Stream（可选 Phase 1.5）：`Accept: text/event-stream`，事件 `token` / `citation` / `done` / `error`。

### 5.3 Phase 2：确认类写操作

```
POST /api/agent/actions/confirm
Body: { actionId, approve: true|false, params? }
```

`actionId` 来自助手消息里的 `pendingAction`（如 organize preview）。

## 6. Tools 规格

### 6.1 Phase 1

#### `search_library`

| 项 | 说明 |
| --- | --- |
| Args | `{ q: string, tagNames?: string[], limit?: number }` |
| 实现 | 复用现网全文/标签搜索（`GET /api/items/search` 同源逻辑）；只搜当前 `user_id` |
| 返回 | `{ hits: [{ itemId, title, snippet, score?, tagNames[] }] }` |
| 限制 | `limit` 默认 8、硬顶 20；snippet 优先命中句，否则标题/摘要截断 |

#### `get_item_excerpt`

| 项 | 说明 |
| --- | --- |
| Args | `{ itemId, maxChars?: number }` |
| 实现 | `aiInput.buildInputText` 后按 `maxChars`（默认 6k～12k）截断；音视频无文稿时返回 `needsTranscript: true`（Phase 1 **不**自动开转写，提示用户去阅读页转写或「需要我先转写这篇吗」待 P1.1） |
| 返回 | `{ title, excerpt, tagNames, contentHash }` |

#### `answer`（内部，非 LLM tool）

编排层根据 tool 结果生成对用户短答；prompt 约束：

- 只依据工具返回的内容，禁止编造库外事实
- 提及具体篇目时必须能在 `citations` 找到对应 `itemId`
- 找不到时直说，并建议换说法或去搜索页用关键词

### 6.2 Phase 2 Tools（包装现网）

每个 tool 调用路径：

1. Orchestrator 解析出 `itemId`（来自用户指定或上一轮 citation）
2. 调用现有 `requestSummary` / `requestMindmap` / …（含门控、queue、转写互斥）
3. 若异步：写入 `agent_tool_runs`，助手消息先回「正在生成解读…」，完成后补一条 assistant 或 patch 原消息
4. 计量：仍走各 service 现有 `usage_events`；Agent 编排本身的规划 token **另计或合并进同池**（建议合并，事件类型 `ai_agent`）

**`organize_preview`**：只返回预览 JSON，与现网 organize sheet 同源；`confirm` 后调 `applyOrganize`。

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
| 规划模型 | `ALIYUN_AI_MODEL_AGENT`（默认可用 `qwen3.8-flash`；复杂规划再升 max） |
| 实现形态 | 优先 **原生 tool-calling**（Thought 隐式/显式均可）；无可靠 tool-call 时再退回文本 ReAct 解析 |
| 单篇重活 | 继续用现网 `ALIYUN_AI_MODEL_SUMMARY` / `TAGS` / 脑图 `ALIYUN_AI_MODEL` |
| Context | 近期 N 轮消息 + 本轮 Thought/Action/Observation；单篇正文仍走 `aiInput` cache_control，避免全文进历史 |
| System prompt | 身份=奏折私人助手；ReAct 规则；能力边界；禁止越权写库；中文；必须 citations |

### 7.3 Phase 1 可先「浅 ReAct」

固定骨架：`search_library`（必要时再 `get_item_excerpt`）→ 一次 Final Answer。  
仍走同一 orchestrator 与消息/trace 形状，便于 P1.1 打开完整多步 ReAct，而不改 API。

## 8. 额度与门控

| 项 | 说明 |
| --- | --- |
| 档位 | 太子+（与解读同级） |
| 计量 | `(prompt - cached) + completion`；事件 `type=ai_agent`（规划+回答）；tool 内总结/脑图继续各自 type 或统一归 `ai_agent` 子字段 `tool` |
| 自动打标 | **仍不走 Agent、仍不计用户额度**（保持现网） |
| 触顶 | 402 + 升级引导；助手页展示本月剩余与现网 usage 一致 |
| 配置 | `USAGE_ENFORCING`；`features.aiAgent` |

`usageService` / App `UsagePlan` 增加 `aiAgent: hasPrince`；升级页权益文案加「私人助手」。

## 9. App 实现要点

### 9.1 路由与入口

- `HomePage` AppBar `actions`：在添加按钮左侧加 `助手` chip（视觉对齐 Figma）
- `AgentPage`（或 `AssistantPage`）：空态 / 线程 / 输入框；出处用接近 `ItemListTile` 的卡片
- 埋点：`agent_open` / `agent_send` / `agent_citation_open` / `agent_upgrade_gate`

### 9.2 状态

- 本地：当前 `conversationId`、消息列表、sending/streaming
- 出处点击 → `ItemReadingPage(openEntry: 'agent')`
- 错误：额度 / 网络 / 空库；空库引导去添加链接

### 9.3 与阅读页 AI 的关系（演进）

| 阶段 | 行为 |
| --- | --- |
| P1 | 阅读页解读/脑图不变；助手独立 |
| P2 | 解读/脑图可「在助手中打开」；底层同一 service |
| P3 | 底栏入口改为唤起助手并带 `bootstrap: { tool, itemId }`；sheet UI 可删或变薄 |

## 10. 检索质量（Phase 1 关键）

1. **先关键词 / 标签检索**（现网），再把 TopK 篇 `get_item_excerpt` 交给模型合成  
2. 用户问「对照 A 和 B」：识别两篇 → 两篇 excerpt → 对比段落  
3. 后续可加：embedding 表（`item_embeddings`）做语义召回；**不要** Phase 1 就上向量，除非关键词明显不够  
4. snippet：优先返回含 query 的句子；禁止把整篇正文塞进 citations UI  

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
| **P2.0 整理** | Tools：summary / mindmap；阅读页可跳转助手 | 助手内生成解读并写入 `ai_meta`；能力条「整理」亮 |
| **P2.1 整理** | Tools：tags / organize（确认条） | 无静默改库 |
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
- `home_page.dart` 入口

## 14. 开放问题

1. 会话历史是否进「账户」二级页，还是助手页内抽屉即可？  
2. Phase 1 无文稿时是否允许助手代开转写（会吃转写分钟）？  
3. 编排 token 与 tool 内 token 是否在用量页拆开展示？  
4. 整理/创作能力条是否对非太子可见（灰态引流）？建议可见、点击进升级。  

## 15. 与现网文档同步清单（实现时勾）

- [ ] `docs/技术实现.md` 新增 §2.6.x 私人助手  
- [ ] `docs/付费规划.md` 权益表加「私人助手」  
- [ ] `docs/DB-SCHEMA.md` 表结构  
- [ ] App Store / 升级页 / 协议文案（上线前）  
- [ ] 埋点白名单 `agent_*`  
