import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/http/zjuServices/courses.dart';
import 'package:celechron/http/zjuServices/network_defense.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/model/todo.dart';
import 'package:celechron/page/flow/flow_controller.dart';
import 'package:celechron/page/task/task_controller.dart';
import 'package:celechron/services/ohos_native_service.dart';
import 'package:celechron/services/todo_task_sync.dart';

/// 内置学在浙大作业详情、附件浏览、文件提交与撤回管理页面。
class HomeworkSubmissionPage extends StatefulWidget {
  final Task? task;
  final Todo? todo;
  final String? activityId;
  final String? courseId;
  final String? title;
  final String? submitUrl;

  const HomeworkSubmissionPage({
    super.key,
    this.task,
    this.todo,
    this.activityId,
    this.courseId,
    this.title,
    this.submitUrl,
  });

  @override
  State<HomeworkSubmissionPage> createState() => _HomeworkSubmissionPageState();
}

class _HomeworkSubmissionPageState extends State<HomeworkSubmissionPage> {
  bool _isLoading = true;
  String? _errorMessage;

  String? _resolvedActivityId;
  String? _resolvedCourseId;
  String _resolvedTitle = '';
  String _resolvedCourseName = '';
  DateTime? _resolvedEndTime;
  String _resolvedSubmitUrl = '';

  Map<String, dynamic>? _activityDetails;
  Map<String, dynamic>? _latestSubmission;
  bool _isSubmitted = false;
  double? _score;
  DateTime? _submittedAt;
  bool _allowRetract = true;

  List<Map<String, dynamic>> _teacherUploads = [];
  List<Map<String, dynamic>> _studentUploads = [];
  String? _teacherComment;

  // 待提交的本地文件与留言
  String? _selectedFileName;
  int? _selectedFileSize;
  Uint8List? _selectedFileBytes;
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _initParameters();
    _loadData();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _initParameters() {
    // 解析 activityId
    if (widget.activityId != null && widget.activityId!.isNotEmpty) {
      _resolvedActivityId = widget.activityId;
    } else if (widget.todo != null && widget.todo!.id.isNotEmpty) {
      _resolvedActivityId = widget.todo!.id;
    } else if (widget.task?.fromUid != null &&
        widget.task!.fromUid!.startsWith('courses-todo:')) {
      _resolvedActivityId =
          widget.task!.fromUid!.substring('courses-todo:'.length);
    }

    // 解析 courseId 与 submitUrl
    String? rawUrl = widget.submitUrl;
    if (rawUrl == null || rawUrl.isEmpty) {
      if (widget.todo != null) {
        rawUrl = widget.todo!.submitUrl;
      } else if (widget.task != null) {
        final match = RegExp(r'https://courses\.zju\.edu\.cn\S+')
            .firstMatch(widget.task!.description);
        rawUrl = match?.group(0);
      }
    }
    _resolvedSubmitUrl =
        rawUrl ?? 'https://courses.zju.edu.cn/user/index#/todo';

    if (widget.courseId != null && widget.courseId!.isNotEmpty) {
      _resolvedCourseId = widget.courseId;
    } else if (widget.todo != null &&
        widget.todo!.resolvedCourseId.isNotEmpty) {
      _resolvedCourseId = widget.todo!.resolvedCourseId;
    } else {
      final match = RegExp(r'/course/(\d+)/learning-activity#/(\d+)')
          .firstMatch(_resolvedSubmitUrl);
      if (match != null) {
        _resolvedCourseId = match.group(1);
        _resolvedActivityId ??= match.group(2);
      }
    }

    // 标题、课程名、截止时间
    if (widget.title != null && widget.title!.isNotEmpty) {
      _resolvedTitle = widget.title!;
    } else if (widget.todo != null) {
      _resolvedTitle = widget.todo!.name;
    } else if (widget.task != null) {
      _resolvedTitle = widget.task!.summary.replaceFirst(RegExp(r'^作业：'), '');
    }

    if (widget.todo != null && widget.todo!.course.isNotEmpty) {
      _resolvedCourseName = widget.todo!.course;
    } else if (widget.task != null) {
      final match = RegExp(r'课程：([^\n]+)').firstMatch(widget.task!.description);
      _resolvedCourseName = match?.group(1) ?? '';
    }

    _resolvedEndTime = widget.todo?.endTime ?? widget.task?.endTime;

    // 先根据本地记录填充初始状态
    if (_resolvedActivityId != null) {
      final recorded = TodoTaskSync.getHomeworkStatus(_resolvedActivityId!);
      if (recorded != null) {
        _score = (recorded['score'] as num?)?.toDouble();
        final completeness = recorded['completeness']?.toString();
        final submittedAtStr = recorded['submitted_at']?.toString();
        if (submittedAtStr != null) {
          _submittedAt = DateTime.tryParse(submittedAtStr);
        }
        if (_score != null || completeness == 'full') {
          _isSubmitted = true;
        }
      }
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final aid = _resolvedActivityId;
    if (aid == null || aid.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = '未找到作业活动标识 (activityId)';
      });
      return;
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    applyZjuNetworkDefense(client,
        connectionTimeout: const Duration(seconds: 10));

    try {
      // 1. 获取作业活动详情
      final details = await Courses.fetchActivityDetails(client, aid);
      if (details != null) {
        _activityDetails = details;
        if (details['title'] != null &&
            details['title'].toString().isNotEmpty) {
          _resolvedTitle = details['title'].toString();
        }
        final rawEndTime = details['end_time']?.toString();
        if (rawEndTime != null && rawEndTime.isNotEmpty) {
          _resolvedEndTime = DateTime.tryParse(rawEndTime) ?? _resolvedEndTime;
        }
        final rawUploads = details['uploads'];
        if (rawUploads is List) {
          _teacherUploads = rawUploads
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
        if (details['allow_retract'] is bool) {
          _allowRetract = details['allow_retract'] as bool;
        }
      }

      // 2. 获取学生提交记录
      final subResp = await Courses.fetchActivitySubmissions(client, aid);
      Map<String, dynamic>? submission;
      if (subResp != null) {
        final subs = subResp['submissions'];
        if (subs is List && subs.isNotEmpty) {
          final first = subs.first;
          if (first is Map) {
            submission = Map<String, dynamic>.from(first);
          }
        } else if (subResp['id'] != null) {
          submission = subResp;
        }
      }

      // 3. 补充查询 activity-reads-for-user
      Map<String, dynamic>? readData;
      if (_resolvedCourseId != null && _resolvedCourseId!.isNotEmpty) {
        final readsResp = await Courses.fetchActivityReadsForCourse(
          client,
          _resolvedCourseId!,
        );
        if (readsResp != null) {
          final list = readsResp['activity_reads'];
          if (list is List) {
            for (final item in list) {
              if (item is Map && item['activity_id']?.toString() == aid) {
                readData = Map<String, dynamic>.from(item);
                break;
              }
            }
          }
        }
      }

      client.close(force: true);

      // 合并状态判定
      bool submitted = false;
      double? score;
      DateTime? submittedAt;
      List<Map<String, dynamic>> studentFiles = [];
      String? teacherComment;

      if (submission != null) {
        _latestSubmission = submission;
        final isDraft = submission['is_draft'] == true;
        if (!isDraft) {
          submitted = true;
        }
        final scoreVal = submission['score'];
        if (scoreVal is num) {
          score = scoreVal.toDouble();
        }
        final createdAtStr = submission['created_time']?.toString() ??
            submission['updated_time']?.toString();
        if (createdAtStr != null) {
          submittedAt = DateTime.tryParse(createdAtStr);
        }
        final uploads = submission['uploads'];
        if (uploads is List) {
          studentFiles = uploads
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
        final reviewComment = submission['review_comment']?.toString();
        if (reviewComment != null && reviewComment.isNotEmpty) {
          teacherComment = reviewComment;
        }
      }

      if (readData != null) {
        final completeness = readData['completeness']?.toString() ?? '';
        final mData = readData['data'];
        if (mData is Map) {
          final sVal = mData['score'];
          if (sVal is num) score ??= sVal.toDouble();
          final sTimeStr = mData['submitted_at']?.toString();
          if (sTimeStr != null) {
            submittedAt ??= DateTime.tryParse(sTimeStr);
          }
        }
        if (completeness == 'full' || score != null) {
          submitted = true;
        } else if (completeness == 'incomplete' || completeness.isEmpty) {
          submitted = false;
        }
      }

      // 同步本地状态缓存
      TodoTaskSync.recordHomeworkStatus(
        aid,
        completeness: submitted ? 'full' : 'incomplete',
        score: score,
        submittedAt: submittedAt,
        clearIfIncomplete: !submitted,
      );

      // 同步 Task 状态
      _syncTaskStatusLocally(submitted, score);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSubmitted = submitted;
          _score = score;
          _submittedAt = submittedAt;
          _studentUploads = studentFiles;
          _teacherComment = teacherComment;
        });
      }
    } catch (e) {
      client.close(force: true);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '获取作业信息失败：$e\n请确保已登录学在浙大，或直接在外部浏览器中操作。';
        });
      }
    }
  }

  void _syncTaskStatusLocally(bool submitted, double? score) {
    final aid = _resolvedActivityId;
    if (aid == null) return;

    bool hasChanged = false;
    if (Get.isRegistered<RxList<Task>>(tag: 'taskList')) {
      final taskList = Get.find<RxList<Task>>(tag: 'taskList');
      for (final t in taskList) {
        if (t.fromUid == 'courses-todo:$aid') {
          final oldStatus = t.status;
          final targetStatus = (submitted || score != null)
              ? TaskStatus.completed
              : (t.endTime.isBefore(DateTime.now())
                  ? TaskStatus.failed
                  : TaskStatus.running);
          if (oldStatus != targetStatus) {
            t.status = targetStatus;
            t.refreshStatus();
            hasChanged = true;
          }
          break;
        }
      }
      if (hasChanged) {
        taskList.refresh();
      }
    }

    if (!hasChanged) {
      // 状态并未发生变化（如仅是点开卡片查看），不触发任务更新，避免影响首页规划状态
      return;
    }

    if (Get.isRegistered<TaskController>()) {
      final tc = Get.find<TaskController>();
      tc.updateDeadlineList();
      tc.saveDeadlineListToDb();
    }

    // 在作业提交界面内部产生的状态同步（用户主动提交/撤回），保持与 FlowController 的规划时间一致，
    // 避免首页规划产生多余的“作业状态已变化”弹窗
    if (Get.isRegistered<FlowController>()) {
      final fc = Get.find<FlowController>();
      fc.updateDeadlineListTime();
    }
  }

  /// 选择本地文件作为附件
  Future<void> _pickAttachment() async {
    try {
      final picked = await OhosNativeService.instance.pickAnyFile();
      if (picked != null) {
        final name = picked['name'] as String?;
        final size = picked['size'] as int?;
        final bytes = picked['bytes'] as Uint8List?;
        if (name != null &&
            name.isNotEmpty &&
            bytes != null &&
            bytes.isNotEmpty) {
          if (mounted) {
            setState(() {
              _selectedFileName = name;
              _selectedFileSize = size ?? bytes.length;
              _selectedFileBytes = bytes;
            });
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('pickAttachment error: $e');
    }
    // 用户取消选取或未选择任何文件，保持静默，不弹提示
  }

  /// 提交作业流程
  Future<void> _submitHomework() async {
    final comment = _commentController.text.trim();
    if (_selectedFileBytes == null && comment.isEmpty) {
      showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('提示'),
          content: const Padding(
            padding: EdgeInsets.only(top: 8.0),
            child: Text('请先选择要上传的文件附件，或在留言框中输入作业内容后再提交。'),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('好的'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('确认提交作业'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text(
            '确定要向学在浙大提交此项作业吗？\n'
            '${_selectedFileName != null ? "附件：$_selectedFileName\n" : ""}'
            '提交后将自动同步任务完成状态。',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定提交'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    applyZjuNetworkDefense(client,
        connectionTimeout: const Duration(seconds: 30));

    try {
      final uploadIds = <int>[];

      // 若有选择本地文件，执行上传
      if (_selectedFileName != null && _selectedFileBytes != null) {
        final uploadId = await Courses.uploadSubmissionFile(
          client,
          fileName: _selectedFileName!,
          fileBytes: _selectedFileBytes!,
        );
        if (uploadId != null) {
          uploadIds.add(uploadId);
        } else {
          throw Exception('文件上传至学在浙大失败，请检查网络或在网页端提交');
        }
      }

      // 执行提交请求
      final success = await Courses.submitHomework(
        client,
        activityId: _resolvedActivityId!,
        uploadIds: uploadIds,
        comment: comment,
      );

      client.close(force: true);

      if (success) {
        setState(() {
          _isSubmitting = false;
          _selectedFileName = null;
          _selectedFileSize = null;
          _selectedFileBytes = null;
          _commentController.clear();
        });

        _syncTaskStatusLocally(true, null);

        if (mounted) {
          await showCupertinoDialog<void>(
            context: context,
            builder: (ctx) => CupertinoAlertDialog(
              title: const Text('🎉 提交成功'),
              content: const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text('作业已成功提交至学在浙大，任务状态已自动同步为已完成！'),
              ),
              actions: [
                CupertinoDialogAction(
                  isDefaultAction: true,
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('好的'),
                ),
              ],
            ),
          );
          _loadData();
        }
      } else {
        throw Exception('学在浙大服务器返回提交未成功，请稍后再试');
      }
    } catch (e) {
      client.close(force: true);
      if (mounted) {
        setState(() => _isSubmitting = false);
        showCupertinoDialog<void>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('提交失败'),
            content: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text('$e\n\n您也可以点击右上角在外部浏览器中完成提交。'),
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('我知道了'),
              ),
              CupertinoDialogAction(
                child: const Text('在浏览器打开'),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  launchUrlString(_resolvedSubmitUrl,
                      mode: LaunchMode.externalApplication);
                },
              ),
            ],
          ),
        );
      }
    }
  }

  /// 撤回提交流程
  Future<void> _retractHomework() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('确认撤回作业'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8.0),
          child: Text('确定要撤回已提交的作业吗？撤回后您可以重新修改附件并再次提交。'),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('撤回提交'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);

    final subId = _latestSubmission?['id']?.toString() ?? '';
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    applyZjuNetworkDefense(client,
        connectionTimeout: const Duration(seconds: 15));

    try {
      final success = await Courses.retractHomework(
        client,
        submissionId: subId,
        activityId: _resolvedActivityId,
      );
      client.close(force: true);

      if (success) {
        // 本地清除记录并恢复任务状态
        TodoTaskSync.recordHomeworkStatus(
          _resolvedActivityId!,
          completeness: 'incomplete',
          clearIfIncomplete: true,
        );
        _syncTaskStatusLocally(false, null);

        if (mounted) {
          setState(() => _isSubmitting = false);
          await showCupertinoDialog<void>(
            context: context,
            builder: (ctx) => CupertinoAlertDialog(
              title: const Text('已撤回'),
              content: const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text('作业已成功撤回，任务状态已重置为待提交。'),
              ),
              actions: [
                CupertinoDialogAction(
                  isDefaultAction: true,
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('我知道了'),
                ),
              ],
            ),
          );
          _loadData();
        }
      } else {
        throw Exception('学在浙大接口未允许撤回，可能是教师已开始批改或已过允许撤回时间');
      }
    } catch (e) {
      client.close(force: true);
      if (mounted) {
        setState(() => _isSubmitting = false);
        showCupertinoDialog<void>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('撤回失败'),
            content: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text('$e'),
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('好的'),
              ),
            ],
          ),
        );
      }
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _cleanHtml(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</div>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          _resolvedCourseName.isNotEmpty
              ? '$_resolvedCourseName · 作业'
              : '作业详情与提交',
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              minSize: 0,
              onPressed: () => launchUrlString(_resolvedSubmitUrl,
                  mode: LaunchMode.externalApplication),
              child: const Icon(CupertinoIcons.compass, size: 22),
            ),
            const SizedBox(width: 14),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minSize: 0,
              onPressed: _isLoading ? null : _loadData,
              child: const Icon(CupertinoIcons.arrow_clockwise, size: 20),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: _isLoading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CupertinoActivityIndicator(radius: 14),
                    SizedBox(height: 12),
                    Text('正在获取学在浙大作业与提交信息...'),
                  ],
                ),
              )
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeaderCard(),
                    const SizedBox(height: 12),
                    if (_errorMessage != null) ...[
                      _buildErrorCard(),
                      const SizedBox(height: 12),
                    ],
                    _buildRequirementsCard(),
                    const SizedBox(height: 12),
                    if (_teacherUploads.isNotEmpty) ...[
                      _buildTeacherUploadsCard(),
                      const SizedBox(height: 12),
                    ],
                    _buildSubmissionCard(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    final now = DateTime.now();
    final isGraded = _score != null;
    final isOverdue = !_isSubmitted &&
        _resolvedEndTime != null &&
        _resolvedEndTime!.isBefore(now);

    Color badgeBg;
    Color badgeFg;
    IconData badgeIcon;
    String badgeText;

    if (isGraded) {
      badgeBg = CupertinoColors.systemOrange.withValues(alpha: 0.15);
      badgeFg = CupertinoColors.systemOrange;
      badgeIcon = CupertinoIcons.star_fill;
      final sText = _score == _score!.roundToDouble()
          ? _score!.toInt().toString()
          : _score!.toStringAsFixed(1);
      badgeText = '已批改 · $sText 分';
    } else if (_isSubmitted) {
      badgeBg = CupertinoColors.systemGreen.withValues(alpha: 0.15);
      badgeFg = CupertinoColors.systemGreen;
      badgeIcon = CupertinoIcons.checkmark_circle_fill;
      badgeText = '已提交（待批改）';
    } else if (isOverdue) {
      badgeBg = CupertinoColors.systemRed.withValues(alpha: 0.12);
      badgeFg = CupertinoColors.systemRed;
      badgeIcon = CupertinoIcons.exclamationmark_circle_fill;
      badgeText = '已逾期';
    } else {
      badgeBg = CupertinoColors.activeBlue.withValues(alpha: 0.12);
      badgeFg = CupertinoColors.activeBlue;
      badgeIcon = CupertinoIcons.clock;
      badgeText = '待提交';
    }

    String ddlStr = '未指定截止时间';
    if (_resolvedEndTime != null) {
      ddlStr =
          '截止时间：${_resolvedEndTime!.year}-${_resolvedEndTime!.month.toString().padLeft(2, '0')}-${_resolvedEndTime!.day.toString().padLeft(2, '0')} ${_resolvedEndTime!.hour.toString().padLeft(2, '0')}:${_resolvedEndTime!.minute.toString().padLeft(2, '0')}';
      if (!isOverdue && !_isSubmitted) {
        final diff = _resolvedEndTime!.difference(now);
        if (diff.inDays > 0) {
          ddlStr += ' (还剩 ${diff.inDays} 天)';
        } else if (diff.inHours > 0) {
          ddlStr += ' (还剩 ${diff.inHours} 小时)';
        } else if (diff.inMinutes > 0) {
          ddlStr += ' (还剩 ${diff.inMinutes} 分钟)';
        }
      }
    }

    return RoundRectangleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _resolvedTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 12, color: badgeFg),
                    const SizedBox(width: 4),
                    Text(
                      badgeText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: badgeFg,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_resolvedCourseName.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '课程：$_resolvedCourseName',
              style: TextStyle(
                fontSize: 13,
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.secondaryLabel, context),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            ddlStr,
            style: TextStyle(
              fontSize: 12,
              color: isOverdue
                  ? CupertinoColors.systemRed
                  : CupertinoDynamicColor.resolve(
                      CupertinoColors.secondaryLabel, context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return RoundRectangleCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(CupertinoIcons.exclamationmark_triangle_fill,
              size: 20, color: CupertinoColors.systemOrange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage ?? '',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequirementsCard() {
    final rawDesc = _activityDetails?['description']?.toString() ?? '';
    final cleaned = _cleanHtml(rawDesc);

    return RoundRectangleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(CupertinoIcons.doc_text, size: 16),
              SizedBox(width: 6),
              Text(
                '作业要求与说明',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            cleaned.isNotEmpty ? cleaned : '教师未填写作业补充说明。',
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: cleaned.isNotEmpty
                  ? CupertinoTheme.of(context).textTheme.textStyle.color
                  : CupertinoDynamicColor.resolve(
                      CupertinoColors.placeholderText, context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeacherUploadsCard() {
    return RoundRectangleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(CupertinoIcons.paperclip, size: 16),
              const SizedBox(width: 6),
              Text(
                '教师附件 (${_teacherUploads.length})',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._teacherUploads.map((file) {
            final name = file['name']?.toString() ?? '附件文件';
            final size = (file['size'] as num?)?.toInt() ?? 0;
            final downloadUrl = file['download_url']?.toString() ??
                '/api/uploads/${file['id']}/blob';
            final fullUrl = downloadUrl.startsWith('http')
                ? downloadUrl
                : 'https://courses.zju.edu.cn$downloadUrl';

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.tertiarySystemFill, context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.doc_fill,
                        size: 20, color: CupertinoColors.activeBlue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500)),
                          if (size > 0)
                            Text(
                              _formatFileSize(size),
                              style: TextStyle(
                                fontSize: 11,
                                color: CupertinoDynamicColor.resolve(
                                    CupertinoColors.secondaryLabel, context),
                              ),
                            ),
                        ],
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      minSize: 0,
                      color: CupertinoColors.activeBlue,
                      borderRadius: BorderRadius.circular(6),
                      onPressed: () => launchUrlString(fullUrl,
                          mode: LaunchMode.externalApplication),
                      child: const Text('下载', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSubmissionCard() {
    return RoundRectangleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isSubmitted
                    ? CupertinoIcons.check_mark_circled_solid
                    : CupertinoIcons.arrow_up_doc,
                size: 16,
                color: _isSubmitted
                    ? CupertinoColors.systemGreen
                    : CupertinoColors.activeBlue,
              ),
              const SizedBox(width: 6),
              Text(
                _isSubmitted ? '提交记录' : '作业提交',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 若已提交：展示提交详情与撤回选项
          if (_isSubmitted) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CupertinoColors.systemGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: CupertinoColors.systemGreen.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(CupertinoIcons.checkmark_alt,
                          size: 16, color: CupertinoColors.systemGreen),
                      const SizedBox(width: 6),
                      Text(
                        _submittedAt != null
                            ? '已于 ${_submittedAt!.year}-${_submittedAt!.month.toString().padLeft(2, '0')}-${_submittedAt!.day.toString().padLeft(2, '0')} ${_submittedAt!.hour.toString().padLeft(2, '0')}:${_submittedAt!.minute.toString().padLeft(2, '0')} 提交'
                            : '已在学在浙大完成提交',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.systemGreen,
                        ),
                      ),
                    ],
                  ),
                  if (_studentUploads.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text('已提交附件：',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    ..._studentUploads.map((file) {
                      final name = file['name']?.toString() ?? '提交文件';
                      final size = (file['size'] as num?)?.toInt() ?? 0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Row(
                          children: [
                            const Icon(CupertinoIcons.paperclip, size: 14),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '$name (${size > 0 ? _formatFileSize(size) : "已上传"})',
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                  if (_latestSubmission?['comment'] != null &&
                      _latestSubmission!['comment'].toString().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '提交留言：${_latestSubmission!['comment']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                  if (_teacherComment != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                            CupertinoColors.systemOrange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '教师评语：$_teacherComment',
                        style: const TextStyle(
                            fontSize: 12, color: CupertinoColors.systemOrange),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_allowRetract && _score == null) ...[
              CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 10),
                color: CupertinoColors.destructiveRed.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                onPressed: _isSubmitting ? null : _retractHomework,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isSubmitting)
                      const CupertinoActivityIndicator(radius: 8)
                    else
                      const Icon(CupertinoIcons.arrow_counterclockwise,
                          size: 15, color: CupertinoColors.destructiveRed),
                    const SizedBox(width: 6),
                    const Text(
                      '撤回作业提交',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.destructiveRed,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ] else ...[
            // 未提交：文件选择器与提交留言
            if (_selectedFileName != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.tertiarySystemFill, context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.doc_fill,
                        size: 20, color: CupertinoColors.activeBlue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_selectedFileName!,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          Text(
                            _formatFileSize(_selectedFileSize ?? 0),
                            style: TextStyle(
                              fontSize: 11,
                              color: CupertinoDynamicColor.resolve(
                                  CupertinoColors.secondaryLabel, context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minSize: 0,
                      onPressed: () {
                        setState(() {
                          _selectedFileName = null;
                          _selectedFileSize = null;
                          _selectedFileBytes = null;
                        });
                      },
                      child: const Icon(CupertinoIcons.clear_circled,
                          size: 18, color: CupertinoColors.systemGrey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 10),
              color: CupertinoDynamicColor.resolve(
                  CupertinoColors.secondarySystemFill, context),
              borderRadius: BorderRadius.circular(8),
              onPressed: _pickAttachment,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(CupertinoIcons.paperclip,
                      size: 16, color: CupertinoColors.activeBlue),
                  const SizedBox(width: 6),
                  Text(
                    _selectedFileName == null ? '选择文件附件' : '重新选择文件',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.activeBlue,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            CupertinoTextField(
              controller: _commentController,
              placeholder: '给教师的留言或作业文字说明（可选）',
              maxLines: 3,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.tertiarySystemFill, context),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 12),

            CupertinoButton.filled(
              padding: const EdgeInsets.symmetric(vertical: 11),
              borderRadius: BorderRadius.circular(8),
              onPressed: _isSubmitting ? null : _submitHomework,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isSubmitting)
                    const CupertinoActivityIndicator(
                        radius: 8, color: CupertinoColors.white)
                  else
                    const Icon(CupertinoIcons.cloud_upload_fill,
                        size: 17, color: CupertinoColors.white),
                  const SizedBox(width: 6),
                  const Text(
                    '提交作业',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: CupertinoColors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
