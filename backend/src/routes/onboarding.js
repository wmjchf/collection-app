const express = require('express');
const { requireAuth } = require('../middleware/auth');
const onboardingSurveyService = require('../services/onboardingSurveyService');
const {
  listInterestOptions,
  AGE_RANGES,
  SOURCES,
  SOURCE_LABELS,
} = require('../services/onboardingInterestCatalog');

const router = express.Router();

router.use(requireAuth);

/** GET /api/onboarding/survey — 状态 + 选项（供 App 渲染） */
router.get('/survey', async (req, res, next) => {
  try {
    const status = await onboardingSurveyService.getSurveyStatus(
      req.auth.userId,
    );
    return res.json({
      ...status,
      options: {
        ageRanges: AGE_RANGES,
        sources: SOURCES.map((id) => ({
          id,
          label: SOURCE_LABELS[id] || id,
        })),
        interests: listInterestOptions(),
      },
    });
  } catch (err) {
    return next(err);
  }
});

/**
 * POST /api/onboarding/survey
 * body: { skipped?: true } | { ageRange, source, interests: string[] }
 */
router.post('/survey', async (req, res, next) => {
  try {
    const result = await onboardingSurveyService.submitSurvey(
      req.auth.userId,
      req.body || {},
    );
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
