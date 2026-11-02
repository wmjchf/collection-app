const { pool } = require('../db');
const tagModuleService = require('./tagModuleService');
const tagService = require('./tagService');
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

async function ensureModule(userId, name) {
  try {
    return await tagModuleService.createModule(userId, name);
  } catch (err) {
    if (err && err.status === 409) {
      const [rows] = await pool.execute(
        `SELECT * FROM tag_modules
         WHERE user_id = :userId AND name = :name
         LIMIT 1`,
        { userId, name },
      );
      if (rows[0]) {
        return { ...tagModuleService.mapModule(rows[0]), tags: [] };
      }
    }
    throw err;
  }
}

async function ensureTag(userId, name, moduleId) {
  try {
    return await tagService.createTag(userId, name, { moduleId });
  } catch (err) {
    if (err && err.status === 409) {
      const [rows] = await pool.execute(
        `SELECT c.*, 0 AS item_count FROM categories c
         WHERE c.user_id = :userId AND c.section = 'tag' AND c.name = :name
         LIMIT 1`,
        { userId, name },
      );
      if (rows[0]) {
        const tag = tagService.mapTag(rows[0]);
        if (tag.moduleId !== moduleId) {
          await tagService.placeTag(userId, tag.id, { moduleId });
          return { ...tag, moduleId };
        }
        return tag;
      }
    }
    throw err;
  }
}

async function seedInterests(userId, interestIds) {
  const seeded = [];
  for (const id of interestIds) {
    const cat = getInterestById(id);
    if (!cat) continue;
    const mod = await ensureModule(userId, cat.name);
    const tags = [];
    for (const tagName of cat.tags) {
      const tag = await ensureTag(userId, tagName, mod.id);
      tags.push(tag.name);
    }
    seeded.push({ id: cat.id, name: cat.name, moduleId: mod.id, tags });
  }
  return seeded;
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

  const seeded = await seedInterests(userId, interests);

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
    seeded,
  };
}

module.exports = {
  getSurveyStatus,
  submitSurvey,
  listInterestOptions,
  AGE_RANGES,
  SOURCES,
};
