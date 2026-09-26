import 'package:flutter/material.dart';
import 'package:super_collection/features/onboarding/first_survey_page.dart';
import 'package:super_collection/features/onboarding/onboarding_page.dart';
import 'package:super_collection/features/onboarding/onboarding_prefs.dart';
import 'package:super_collection/features/onboarding/onboarding_survey_repository.dart';
import 'package:super_collection/features/onboarding/survey_prefs.dart';
import 'package:super_collection/features/shell/main_shell.dart';

/// 登录 / 冷启动后首页：问卷 → 三种收藏引导 → MainShell
Future<Widget> resolvePostAuthHome({
  required int userId,
  bool? surveyCompletedFromServer,
}) async {
  var surveyDone = await SurveyPrefs.isDone(userId: userId);

  if (!surveyDone && surveyCompletedFromServer == true) {
    await SurveyPrefs.markDone(userId: userId);
    surveyDone = true;
  }

  if (!surveyDone) {
    try {
      final status = await OnboardingSurveyRepository().fetchStatus();
      if (status.surveyCompleted) {
        await SurveyPrefs.markDone(userId: userId);
        surveyDone = true;
      }
    } catch (_) {}
  }

  if (!surveyDone) {
    return FirstSurveyPage(userId: userId);
  }

  final seenWays = await OnboardingPrefs.isSeen(userId: userId);
  if (!seenWays) {
    return OnboardingPage(userId: userId);
  }
  return const MainShell();
}

/// 问卷提交/跳过之后：进三种收藏引导或首页
Future<Widget> nextAfterSurvey({required int userId}) async {
  final seenWays = await OnboardingPrefs.isSeen(userId: userId);
  if (!seenWays) {
    return OnboardingPage(userId: userId);
  }
  return const MainShell();
}
