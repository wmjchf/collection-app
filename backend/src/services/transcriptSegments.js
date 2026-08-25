/** 分段转写：枚举可转写源、读写 transcript_segments JSON */

const SEGMENT_VIDEO_URL = 'video_url';

function parseSegments(raw) {
  if (raw == null) return {};
  try {
    const o = typeof raw === 'string' ? JSON.parse(raw) : raw;
    if (!o || typeof o !== 'object' || Array.isArray(o)) return {};
    return o;
  } catch {
    return {};
  }
}

function hasInlineVideos(content) {
  return /!v\[[^\]]*\]\([^)\s]+\)/i.test(String(content || ''));
}

function listInlineVideoUrls(content) {
  const urls = [];
  const re = /!v\[[^\]]*\]\(([^)\s]+)\)/gi;
  const s = String(content || '');
  let m = re.exec(s);
  while (m) {
    const u = (m[1] || '').trim();
    if (u) urls.push(u);
    m = re.exec(s);
  }
  return urls;
}

function isHttpsMedia(url) {
  const u = String(url || '').trim();
  return /^https?:\/\//i.test(u) && !/^qqvid:/i.test(u);
}

function normalizeCues(raw) {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((c) => {
      if (!c || typeof c !== 'object') return null;
      const text = String(c.text || '').trim();
      if (!text) return null;
      const startMs =
        c.startMs == null || !Number.isFinite(Number(c.startMs))
          ? null
          : Math.max(0, Math.round(Number(c.startMs)));
      const endMs =
        c.endMs == null || !Number.isFinite(Number(c.endMs))
          ? null
          : Math.max(0, Math.round(Number(c.endMs)));
      const speakerRaw = c.speaker;
      const speaker =
        speakerRaw == null || speakerRaw === ''
          ? null
          : Number(speakerRaw);
      return {
        startMs,
        endMs,
        speaker: Number.isFinite(speaker) ? speaker : null,
        text,
      };
    })
    .filter(Boolean);
}

function normalizeSegment(seg) {
  if (!seg || typeof seg !== 'object') {
    return {
      status: 'none',
      text: null,
      cues: [],
      error: null,
      taskId: null,
      mediaUrl: null,
      transcribedAt: null,
      phase: null,
      phaseLabel: null,
    };
  }
  const phase = seg.phase == null || seg.phase === '' ? null : String(seg.phase);
  const phaseLabel =
    seg.phaseLabel == null || seg.phaseLabel === ''
      ? null
      : String(seg.phaseLabel);
  return {
    status: seg.status || 'none',
    text: seg.text ?? null,
    cues: normalizeCues(seg.cues),
    error: seg.error ?? null,
    taskId: seg.taskId ?? null,
    mediaUrl: seg.mediaUrl ?? null,
    transcribedAt: seg.transcribedAt ?? null,
    phase,
    phaseLabel,
  };
}

/** 与阅读页一致：有内嵌 !v 则只枚举正文各段，否则用顶栏 video_url */
function listTranscriptTargets(row) {
  const content = String(row.content || '');
  const segments = parseSegments(row.transcript_segments);
  const targets = [];

  if (hasInlineVideos(content)) {
    const urls = listInlineVideoUrls(content);
    urls.forEach((url, i) => {
      const segmentKey = `inline:${i}`;
      const seg = normalizeSegment(segments[segmentKey]);
      targets.push({
        segmentKey,
        label: `文中视频 ${i + 1}`,
        mediaUrl: isHttpsMedia(url) ? url : null,
        needsClientResolve: !isHttpsMedia(url),
        status: seg.status,
        text: seg.text,
        cues: seg.cues,
        error: seg.error,
        transcribedAt: seg.transcribedAt,
      });
    });
    return targets;
  }

  const video = String(row.video_url || '').trim();
  if (!video) return targets;

  const seg = normalizeSegment(segments[SEGMENT_VIDEO_URL]);
  targets.push({
    segmentKey: SEGMENT_VIDEO_URL,
    label: '音频',
    mediaUrl: isHttpsMedia(video) ? video : null,
    needsClientResolve: !isHttpsMedia(video),
    status: seg.status,
    text: seg.text,
    cues: seg.cues,
    error: seg.error,
    transcribedAt: seg.transcribedAt,
  });
  return targets;
}

function hasPendingSegment(segments) {
  return Object.values(segments).some((s) => s && s.status === 'pending');
}

function findPendingSegmentKey(segments) {
  for (const [key, seg] of Object.entries(segments)) {
    if (seg && seg.status === 'pending') return key;
  }
  return null;
}

function resolveMediaUrlForSegment(row, segmentKey, clientMediaUrl) {
  if (clientMediaUrl && isHttpsMedia(clientMediaUrl)) {
    return String(clientMediaUrl).trim();
  }
  const targets = listTranscriptTargets(row);
  const target = targets.find((t) => t.segmentKey === segmentKey);
  if (!target) return null;
  return target.mediaUrl;
}

function setSegment(segments, segmentKey, patch) {
  const cur = normalizeSegment(segments[segmentKey]);
  segments[segmentKey] = { ...cur, ...patch };
  return segments;
}

/** 搜索匹配：拼接各段文稿 */
function allTranscriptText(segments) {
  return Object.values(segments)
    .map((s) => (s && s.text ? String(s.text) : ''))
    .filter(Boolean)
    .join('\n');
}

function mapSegmentsForApi(segments) {
  const out = {};
  for (const [key, seg] of Object.entries(segments)) {
    const n = normalizeSegment(seg);
    out[key] = {
      status: n.status,
      text: n.text,
      cues: n.cues,
      error: n.error,
      transcribedAt: n.transcribedAt,
      phase: n.phase,
      phaseLabel: n.phaseLabel,
      hasText: !!(n.text && String(n.text).trim()),
    };
  }
  return out;
}

module.exports = {
  SEGMENT_VIDEO_URL,
  parseSegments,
  hasInlineVideos,
  listInlineVideoUrls,
  listTranscriptTargets,
  hasPendingSegment,
  findPendingSegmentKey,
  resolveMediaUrlForSegment,
  setSegment,
  allTranscriptText,
  mapSegmentsForApi,
  isHttpsMedia,
  normalizeSegment,
  normalizeCues,
};
