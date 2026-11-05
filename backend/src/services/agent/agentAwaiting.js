/**
 * 会话步骤态：助手回合可挂 awaiting，下一轮统一判定「答中 / 换题」。
 * 存在 assistant.tool_calls_json.awaiting；确认条仍用 pendingAction。
 */

const AWAITING = {
  ORGANIZE_PREFERENCE: 'organize_preference',
  ORGANIZE_CONFIRM: 'organize_confirm',
  TAG_EDIT_PREFERENCE: 'tag_edit_preference',
  TAG_EDIT_CONFIRM: 'tag_edit_confirm',
};

function resolveAwaiting(history) {
  const list = Array.isArray(history) ? history : [];
  for (let i = list.length - 1; i >= 0; i -= 1) {
    const m = list[i];
    if (m?.role !== 'assistant') continue;

    const pa = m.pendingAction;
    if (pa && pa.status === 'pending') {
      if (pa.type === 'organize_tags') {
        return { kind: AWAITING.ORGANIZE_CONFIRM, source: 'pendingAction' };
      }
      if (pa.type === 'item_tag_edit') {
        return { kind: AWAITING.TAG_EDIT_CONFIRM, source: 'pendingAction' };
      }
    }

    const raw = m.awaiting || null;
    if (raw && Object.values(AWAITING).includes(String(raw))) {
      return {
        kind: String(raw),
        source: 'awaiting',
        meta: m.awaitingMeta && typeof m.awaitingMeta === 'object'
          ? m.awaitingMeta
          : null,
      };
    }

    // 兼容旧消息：文案嗅探询问态（模型手写或漏挂 awaiting）
    if (looksLikeOrganizePreferenceAskContent(m.content)) {
      return {
        kind: AWAITING.ORGANIZE_PREFERENCE,
        source: 'legacy_content',
      };
    }
    if (looksLikeTagEditPreferenceAskContent(m.content)) {
      const meta = extractTagEditAskMeta(m);
      return {
        kind: AWAITING.TAG_EDIT_PREFERENCE,
        source: 'legacy_content',
        meta,
      };
    }
    break;
  }
  return null;
}

function looksLikeOrganizePreferenceAskContent(content) {
  const c = String(content || '');
  return (
    /听听你的分类意见|你更希望怎么分|分类意见/.test(c) &&
    /\*\*按行业\*\*|\*\*按主题\*\*|\*\*你看着分\*\*/.test(c)
  );
}

/** 上文在问「标签怎么改」（含系统询问与模型变体文案） */
function looksLikeTagEditPreferenceAskContent(content) {
  const c = String(content || '');
  if (!c) return false;
  return (
    /想怎么改|想怎么调|可以说[「"]加上|去掉某某|加上某某|我来出预览/.test(c) &&
    /标签/.test(c)
  );
}

function extractTagEditAskMeta(message) {
  const meta = { itemId: null, title: '' };
  const id = Number(message?.citations?.[0]?.itemId);
  if (Number.isFinite(id) && id > 0) meta.itemId = id;
  const title = String(message?.citations?.[0]?.title || '').trim();
  if (title) meta.title = title;
  if (!meta.itemId && message?.awaitingMeta?.itemId) {
    const mid = Number(message.awaitingMeta.itemId);
    if (Number.isFinite(mid) && mid > 0) meta.itemId = mid;
  }
  if (!meta.title && message?.awaitingMeta?.title) {
    meta.title = String(message.awaitingMeta.title || '').trim();
  }
  return meta.itemId || meta.title ? meta : null;
}

/** 短句像单个标签名（模型漏填时兜底「直接丢一个名」） */
function looksLikeBareTagName(text) {
  const t = String(text || '').trim();
  if (!t || t.length > 24) return false;
  if (/[。！？\n]/.test(t)) return false;
  if (/^(取消|不做了|算了|不用了|可以|确认|好的|行|嗯)[。.!！]?$/.test(t)) {
    return false;
  }
  if (
    /(加上|去掉|删掉|删除|换成|改成|调整|归类|对照|对比|搜索|查找|收藏|合适|不对|不好|不行)/.test(
      t,
    )
  ) {
    return false;
  }
  return /^[\u4e00-\u9fffA-Za-z0-9][\u4e00-\u9fffA-Za-z0-9 ·_\-]{0,23}$/.test(
    t,
  );
}

/** 明确换题信号（与当前 awaiting 无关的新任务） */
function looksLikeTopicSwitch(text) {
  const t = String(text || '').trim();
  if (!t) return false;

  if (
    /对照|对比|比较/.test(t) &&
    (/「[^」]+」|《[^》]+》/.test(t) ||
      /这[两几多]篇|两篇|几篇/.test(t) ||
      t.length <= 24)
  ) {
    return true;
  }

  if (
    /帮我找|查找关于|搜一下|有没有.{0,12}收藏|最近收藏了/.test(t) ||
    /现在有哪些标签|还有哪些标签|库里有哪些标签/.test(t) ||
    /深挖|核心观点|这篇(主要)?在讲|解读一下|再展开/.test(t) ||
    /最近收藏了哪些|盘点一下收藏|我收藏了什么/.test(t)
  ) {
    return true;
  }

  // 点名改标（非整库归类）
  if (
    /(改|换|加|删|调整).{0,8}标签/.test(t) &&
    !/(归类|分类|建架|整理归类)/.test(t)
  ) {
    return true;
  }

  return false;
}

/** 是否像在回答当前 awaiting */
function looksLikeAwaitingAnswer(text, awaiting) {
  if (!awaiting?.kind) return false;
  const t = String(text || '').trim();
  if (!t) return false;

  if (awaiting.kind === AWAITING.ORGANIZE_PREFERENCE) {
    if (/^(取消|不做了|算了|不用了)[。.!！]?$/.test(t)) return true;
    return (
      /^(按行业|按主题|自定义|你看着分|你看着|由你来分|你来分|你定)([归类分法].*)?[。.!！]?$/.test(
        t,
      ) ||
      /按.{0,12}(行业|主题|类型|领域|品类)/.test(t) ||
      /你看着|你来分|你定|随便分|自动分|都可以|随意|你决定/.test(t) ||
      /我有自己的分法|自定义/.test(t) ||
      /分成|归成|侧重|优先|新建一个|用现有/.test(t)
    );
  }

  if (awaiting.kind === AWAITING.TAG_EDIT_PREFERENCE) {
    // 改标询问：不靠词表猜说法；取消算答中，其余由 shouldContinueAwaiting 默认续上
    return /^(取消|不做了|算了|不用了)[。.!！]?$/.test(t);
  }

  if (
    awaiting.kind === AWAITING.ORGANIZE_CONFIRM ||
    awaiting.kind === AWAITING.TAG_EDIT_CONFIRM
  ) {
    if (/^(取消|不做了|算了|不用了)[。.!！]?$/.test(t)) return true;
    if (/^(可以|确认|好的|行|嗯|没问题|就这样|确认整理|确认调整)[。.!！]?$/.test(t)) {
      return true;
    }
    // 修正预览仍算答在确认步
    return /漏(掉|了)?|忘了|遗漏|补上|还有.{0,12}标签/.test(t);
  }

  return false;
}

/**
 * 当前 awaiting 下本轮是否应继续该流程。
 * 换题且并非在回答 awaiting → 放行新意图。
 *
 * 改标询问：只要没换题，就钉住 tag_edit，具体加删由 plan 模型填 tagEdit
 * （不靠「不太合适」等词表）。归类询问仍只接受明确分法短答。
 */
function shouldContinueAwaiting(text, awaiting) {
  if (!awaiting?.kind) return false;
  if (looksLikeAwaitingAnswer(text, awaiting)) return true;
  if (looksLikeTopicSwitch(text)) return false;
  if (awaiting.kind === AWAITING.TAG_EDIT_PREFERENCE) {
    return true;
  }
  // 归类询问：不含糊吞掉任意短句；只接受明确答中
  if (awaiting.kind === AWAITING.ORGANIZE_PREFERENCE) {
    return false;
  }
  return false;
}

/** 包装写入 tool_calls_json 的对象 */
function toolPayload(
  steps,
  { awaiting = null, pendingAction = null, awaitingMeta = null } = {},
) {
  const payload = { steps: Array.isArray(steps) ? steps : steps || [] };
  if (awaiting) payload.awaiting = awaiting;
  if (pendingAction) payload.pendingAction = pendingAction;
  if (awaitingMeta && typeof awaitingMeta === 'object') {
    payload.awaitingMeta = awaitingMeta;
  }
  return payload;
}

module.exports = {
  AWAITING,
  resolveAwaiting,
  looksLikeTopicSwitch,
  looksLikeAwaitingAnswer,
  shouldContinueAwaiting,
  looksLikeOrganizePreferenceAskContent,
  looksLikeTagEditPreferenceAskContent,
  looksLikeBareTagName,
  toolPayload,
};
