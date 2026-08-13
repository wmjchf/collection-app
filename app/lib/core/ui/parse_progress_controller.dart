import 'package:flutter/foundation.dart';

enum ParseProgressPhase { hidden, running, success, failed }

/// 解析进度条状态（展示在底栏上方，与普通 Toast 分离）
class ParseProgressController extends ChangeNotifier {
  ParseProgressController._();
  static final ParseProgressController instance = ParseProgressController._();

  ParseProgressPhase phase = ParseProgressPhase.hidden;
  String title = '正在解析内容';
  String subtitle = '拉取标题、封面与正文…';
  int? itemId;

  bool get isVisible => phase != ParseProgressPhase.hidden;

  void start({
    int? itemId,
    String title = '正在解析内容',
    String subtitle = '拉取标题、封面与正文…',
  }) {
    this.itemId = itemId;
    this.title = title;
    this.subtitle = subtitle;
    phase = ParseProgressPhase.running;
    notifyListeners();
  }

  void markSuccess({
    String title = '解析完成',
    String subtitle = '标题与正文已就绪',
  }) {
    this.title = title;
    this.subtitle = subtitle;
    phase = ParseProgressPhase.success;
    notifyListeners();
  }

  void markFailed({
    String title = '解析失败',
    String subtitle = '可稍后在详情中重试',
  }) {
    this.title = title;
    this.subtitle = subtitle;
    phase = ParseProgressPhase.failed;
    notifyListeners();
  }

  void hide() {
    phase = ParseProgressPhase.hidden;
    itemId = null;
    notifyListeners();
  }
}
