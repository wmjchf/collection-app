# 数据库表结构（第一期）

库名：`collection`  
字符集：`utf8mb4` / `utf8mb4_unicode_ci`  
引擎：`InnoDB`

## 账号与登录

- 第一期：**手机号 + 短信验证码登录**（登录即注册）
- 短信能力：**阿里云号码认证**（`Dypnsapi`：`SendSmsVerifyCode` / `CheckSmsVerifyCode`）
- 校验通过后发自有登录态（如 JWT access + refresh）；**验证码明文不落库**（由阿里云生成并校验）

---

## 产品模型（树 + 多维归属）

```
第一层 section（分区，不建表，用枚举）
  ├─ system   系统分类
  ├─ folder   收藏夹
  ├─ tag      标签
  └─ other    其他
       │
       ▼
第二层 categories（具体入口，含「未分类」与用户自建标签等）
       │
       ▼
第三层 items（一条可同时命中多个第二层：多标签 + 多系统规则）
```

| 第一层 | 第二层例子 | 一条 item 与第二层关系 |
| --- | --- | --- |
| system | 未读 / 所有 / 今天 / 星标 / 解析 / 标注 | **规则命中**（不算归属边） |
| folder | **未分类** / 用户自建夹 | **恰好一个**（`items.folder_id`） |
| tag | （仅用户自建） | **0～N 个**（`item_tags`） |
| other | 已归档 / 最近删除 | **状态字段**（`is_archived` / `deleted_at`） |

**多用户约定**

- `user_id = 0`：系统预置第二层（全局共享，仅导航/默认未分类）
- `user_id > 0`：该用户自建的收藏夹 / 标签
- `items.user_id` 必填；列表与写操作均按当前用户隔离
- 新用户首条收藏：`folder_id` 指向系统「未分类」（`user_id=0, code=uncategorized`）

---

## 表一览

| 表 | 说明 |
| --- | --- |
| `users` | 用户（手机号） |
| `user_sessions` | 登录会话 / refresh |
| `sms_send_logs` | 发码流水（限流/审计；验证码本身不存） |
| `categories` | 第二层分类 |
| `items` | 收藏条目（含 `transcript_segments` 分段转写） |
| `item_tags` | 条目 ↔ 标签 |
| `annotations` | 阅读标注 |
| `usage_events` | 用量事件（转写秒 / AI token） |
| `subscriptions` | 订阅（Pro；支付前可有 `source=dev`） |
| `ai_preference_events` | AI 偏好方向 |
| `home_roam_cache` | 首页漫游缓存 |

---

## 1. `users`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | BIGINT UNSIGNED PK AI | |
| phone | VARCHAR(20) NOT NULL | 国内手机号，唯一 |
| nickname | VARCHAR(64) NULL | 默认可用「用户」+ 手机号后四位 |
| avatar_url | VARCHAR(512) NULL | |
| status | ENUM('active','disabled') NOT NULL DEFAULT 'active' | |
| last_login_at | DATETIME(3) NULL | |
| created_at / updated_at | DATETIME(3) | |

---

## 2. `user_sessions`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | BIGINT UNSIGNED PK AI | |
| user_id | BIGINT UNSIGNED NOT NULL | FK → users |
| refresh_token_hash | CHAR(64) NOT NULL | refresh token 的 SHA-256 |
| device_info | VARCHAR(255) NULL | 可选 |
| expires_at | DATETIME(3) NOT NULL | |
| revoked_at | DATETIME(3) NULL | 登出/失效 |
| created_at | DATETIME(3) NOT NULL | |

---

## 3. `sms_send_logs`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | BIGINT UNSIGNED PK AI | |
| phone | VARCHAR(20) NOT NULL | |
| scene | VARCHAR(32) NOT NULL DEFAULT 'login' | |
| provider_request_id | VARCHAR(64) NULL | 阿里云 RequestId |
| created_at | DATETIME(3) NOT NULL | |

用于同一手机号发码间隔、日限额等；**不存验证码**。

---

## 4. `categories`（第二层）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | BIGINT UNSIGNED PK AI | |
| user_id | BIGINT UNSIGNED NOT NULL DEFAULT 0 | 0=系统预置 |
| section | ENUM('system','folder','tag','other') | |
| code | VARCHAR(32) NULL | 系统入口键；用户自建为 NULL |
| name | VARCHAR(64) NOT NULL | |
| is_system | TINYINT(1) NOT NULL DEFAULT 0 | |
| sort_order | INT NOT NULL DEFAULT 0 | |
| created_at / updated_at | DATETIME(3) | |

约束：`UNIQUE (user_id, section, name)`  
系统 `code` 由 seed 保证唯一（`user_id=0`）。

### 预置（user_id = 0）

| section | code | name |
| --- | --- | --- |
| system | unread / all / today / starred / parsed / annotated | 未读/所有/今天/星标/解析/标注 |
| system | recent_read | 最近阅读（系统筛选；首页「查看更多」进入此列表） |
| folder | uncategorized | 未分类 |
| other | archived | 已归档（不在 App 导航展示；`filter=archived` API 仍可用） |
| system | trash | 回收站（原 other，见 `009_trash_system_section.sql`） |

---

## 5. `items`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| user_id | BIGINT UNSIGNED NOT NULL | FK → users |
| folder_id | BIGINT UNSIGNED NOT NULL | 默认系统未分类 |
| is_starred / is_unread / is_archived / deleted_at | … | 同前 |
| **last_read_at** | DATETIME(3) NULL | **最近一次打开本地阅读页的时间**；NULL=从未阅读 |
| … | … | url、解析字段、备注等 |

去重：同一用户下按 `canonical_url`（或 url）判重，索引建议 `(user_id, canonical_url(255))`。  
首页「最近阅读」索引：`(user_id, last_read_at)`。

**音视频转写（分段，独立于 `content`）**

| 字段 | 说明 |
| --- | --- |
| `transcript_segments` | JSON：`{segmentKey:{status,text,cues,error,taskId,mediaUrl,transcribedAt,phase?,phaseLabel?}}`；`cues` 为 `[{startMs,endMs,speaker,text}]`；pending 时 `phase`/`phaseLabel` 为粗粒度进度 |

segmentKey：`video_url`（顶栏，仅无内嵌 `!v` 时）或 `inline:N`。  
API：`GET …/transcript-targets`、`POST …/transcript`（body.segmentKey）、`GET …/transcript-status`。  
迁移：`backend/sql/007_transcript_segments.sql`；执行：`cd backend && pnpm db:migrate:007`（或 `pnpm db:migrate` 跑全部未执行增量）。

**阅读时写入**：进入阅读页 → `last_read_at = NOW()`，且 `is_unread = 0`。

---

## 6. `item_tags` / 7. `annotations`

同前；数据隔离通过 `items.user_id` 间接保证（操作前校验 item 归属）。

---

## 登录 API（约定）

| 接口 | 说明 |
| --- | --- |
| `POST /api/auth/sms/send` | 手机号 → 调阿里云 SendSmsVerifyCode |
| `POST /api/auth/sms/login` | 手机号 + 验证码 → CheckSmsVerifyCode → 无用户则创建 → 返回 token |
| `POST /api/auth/logout` | 作废 refresh |
| `GET /api/me` | 当前用户 |

## 收藏夹 API（约定）

| 接口 | 说明 |
| --- | --- |
| `GET /api/folders` | 系统「未分类」+ 当前用户自建；含 `itemCount` |
| `POST /api/folders` | body `{ name }` 新建；不可与未分类/已有夹重名 |
| `DELETE /api/folders/:id` | 仅自建夹；夹内条目移回「未分类」，不删条目 |

## 标签 API（约定）

| 接口 | 说明 |
| --- | --- |
| `GET /api/tags` | 当前用户自建标签；含 `itemCount` |
| `POST /api/tags` | body `{ name }` 新建 |
| `PATCH /api/tags/:id` | body `{ name }` 重命名自建标签 |
| `DELETE /api/tags/:id` | 仅自建标签；解除 `item_tags` 关联，不删条目 |

## 系统筛选 API（约定）

| 接口 | 说明 |
| --- | --- |
| `GET /api/system-filters` | 未读/所有/今天/星标/解析/标注/最近阅读 + 数量；`tzOffsetMinutes` 可选（默认 480） |
| `GET /api/items?filter=` | 按系统筛选列条目；`filter` 同上；支持 `limit`/`offset`/`tzOffsetMinutes` |
| `GET /api/home` | 首页两板块：未读 / 漫游（`randomPick`），各最多 3 条；漫游默认缓存 4h，`refreshRandom=1` 强制换一批 |

未读无数据时 `countLabel` 为「无」；列表默认排除已删除与已归档。

环境变量（示例）：`ALIYUN_ACCESS_KEY_ID` / `ALIYUN_ACCESS_KEY_SECRET` / `ALIYUN_SMS_SIGN_NAME` / `ALIYUN_SMS_TEMPLATE_CODE`

---

## `subscriptions`（迁移 `015`）

| 字段 | 说明 |
| --- | --- |
| user_id | FK → users |
| plan | 目前仅 `pro` |
| status | `active` / `expired` / `cancelled` |
| source | `manual` / `dev` / `apple` / `google` / `wechat` / `alipay` … |
| external_id | 商店订单号（支付接入后） |
| expires_at | NULL=不限期；有效 Pro = active 且未过期 |
| meta | JSON |

当前是否 Pro：查有效 active 行；额度数字在环境变量（`FREE_*` / `PRO_*`），不写进本表。

---

## 二期预留

- 收藏夹嵌套（`categories.parent_id`）
- 一键登录（运营商取号，同属号码认证，可后加）
- 支付校验与商店回调写入 `subscriptions`

## DDL

见 [`backend/sql/001_schema.sql`](../backend/sql/001_schema.sql) 与增量 `backend/sql/015_subscriptions.sql`
