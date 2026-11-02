const { pool } = require('../db');
const {
  AGE_RANGES,
  SOURCES,
  listInterestOptions,
  getInterestById,
} = require('./onboardingInterestCatalog');

async function getSurveyStatus(userId) {
  const [rows] = await pool.execute(
    `SELECT survey_completed_at, survey_age_range, survey_source, survey_interests
     FROM users WHERE id = :userId LIMIT 1`,
    { userId },
  );
  const row = rows[0];
  if (!row) {
    throw Object.assign(new Error('用户不存在'), { status: 404 });
  }
  return {
    surveyCompleted: !!row.survey_completed_at,
    ageRange: row.survey_age_range || null,
    source: row.survey_source || null,
    interests: parseInterests(row.survey_interests),
  };
}

function parseInterests(raw) {
  if (raw == null) return [];
  if (Array.isArray(raw)) return raw.map(String);
  if (typeof raw === 'string') {
    try {
      const parsed = JSON.parse(raw);
      return Array.isArray(parsed) ? parsed.map(String) : [];
    } catch {
      return [];
    }
  }
  return [];
}

/**
 * @param {{ skipped?: boolean, ageRange?: string, source?: string, interests?: string[] }} body
 */
async function submitSurvey(userId, body) {
  const skipped = body?.skipped === true;
  const status = await getSurveyStatus(userId);
  if (status.surveyCompleted) {
    return { ok: true, alreadyCompleted: true, ...status };
  }

  if (skipped) {
    await pool.execute(
      `UPDATE users
       SET survey_completed_at = CURRENT_TIMESTAMP(3),
           survey_age_range = NULL,
           survey_source = NULL,
           survey_interests = NULL
       WHERE id = :userId`,
      { userId },
    );
    return { ok: true, skipped: true, surveyCompleted: true };
  }

  const ageRange = String(body?.ageRange || '').trim();
  const source = String(body?.source || '').trim();
  const interestsRaw = Array.isArray(body?.interests) ? body.interests : [];
  const interests = [
    ...new Set(interestsRaw.map((id) => String(id || '').trim()).filter(Boolean)),
  ];

  if (!AGE_RANGES.includes(ageRange)) {
    throw Object.assign(new Error('请选择年龄段'), { status: 400 });
  }
  if (!SOURCES.includes(source)) {
    throw Object.assign(new Error('请选择来源'), { status: 400 });
  }
  if (interests.length === 0) {
    throw Object.assign(new Error('请至少选择一个兴趣'), { status: 400 });
  }
  for (const id of interests) {
    if (!getInterestById(id)) {
      throw Object.assign(new Error('兴趣选项无效'), { status: 400 });
    }
  }

  // 只记录兴趣偏好，不预置归类匣 / 标签
  await pool.execute(
    `UPDATE users
     SET survey_completed_at = CURRENT_TIMESTAMP(3),
         survey_age_range = :ageRange,
         survey_source = :source,
         survey_interests = :interests
     WHERE id = :userId`,
    {
      userId,
      ageRange,
      source,
      interests: JSON.stringify(interests),
    },
  );

  return {
    ok: true,
    skipped: false,
    surveyCompleted: true,
    ageRange,
    source,
    interests,
  };
}

module.exports = {
  getSurveyStatus,
  submitSurvey,
  listInterestOptions,
  AGE_RANGES,
  SOURCES,
};
