import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:celechron/design/app_notification.dart';
import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/http/zjuServices/courses.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:celechron/http/zjuServices/network_defense.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/model/todo.dart';
import 'package:celechron/page/flow/flow_controller.dart';
import 'package:celechron/page/task/task_controller.dart';
import 'package:celechron/services/file_download_share_helper.dart';
import 'package:celechron/services/ohos_native_service.dart';
import 'package:celechron/services/todo_task_sync.dart';
import 'package:celechron/utils/json_utils.dart';

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

  /// 计算多附件上传阶段的归一化按钮进度值（0.04 ~ 0.90 留给上传，0.94+ 留给最终提交）
  @visibleForTesting
  static double computeUploadProgress({
    required int uploadedBytesBefore,
    required int currentFileSentBytes,
    required int currentFileTotalBytes,
    required int totalBytes,
    required int fileIndex,
    required int fileCount,
  }) {
    if (fileCount <= 0) return 0.9;
    final clampedSent = currentFileTotalBytes > 0
        ? currentFileSentBytes.clamp(0, currentFileTotalBytes)
        : 0;
    double fraction;
    if (totalBytes > 0) {
      fraction = ((uploadedBytesBefore + clampedSent) / totalBytes).clamp(
        0.0,
        1.0,
      );
    } else {
      final filePart = currentFileTotalBytes > 0
          ? (clampedSent / currentFileTotalBytes).clamp(0.0, 1.0)
          : 1.0;
      fraction = ((fileIndex + filePart) / fileCount).clamp(0.0, 1.0);
    }
    return (0.04 + fraction * 0.86).clamp(0.04, 0.90);
  }

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
  final Set<String> _downloadingAttachments = <String>{};
  final Map<String, String> _downloadedAttachments = <String, String>{};
  final Map<String, String> _downloadedAttachmentNames = <String, String>{};

  String _attachmentRecordKey(String attKey) => 'homework|$attKey';

  Future<void> _refreshAttachmentDownloadStates() async {
    final nextPaths = <String, String>{};
    final nextNames = <String, String>{};
    for (final file in _teacherUploads) {
      final uploadId = (file['id'] as num?)?.toInt() ?? 0;
      final referenceId = (file['reference_id'] as num?)?.toInt() ?? 0;
      final downloadUrl =
          file['download_url']?.toString() ?? '/api/uploads/${file['id']}/blob';
      final fullUrl = downloadUrl.startsWith('http')
          ? downloadUrl
          : 'https://courses.zju.edu.cn$downloadUrl';
      final attKey = '${uploadId}_${referenceId}_$fullUrl';
      final rec = await FileDownloadShareHelper.getDownloadRecord(
        _attachmentRecordKey(attKey),
      );
      if (rec != null) {
        nextPaths[attKey] = rec.savedPath;
        nextNames[attKey] = rec.fileName;
      }
    }
    if (mounted) {
      setState(() {
        _downloadedAttachments
          ..clear()
          ..addAll(nextPaths);
        _downloadedAttachmentNames
          ..clear()
          ..addAll(nextNames);
      });
    }
  }

  Future<void> _downloadOrShareAttachment({
    required String attKey,
    required String name,
    required String fullUrl,
    required int size,
    int uploadId = 0,
    int referenceId = 0,
    required bool share,
  }) async {
    if (_downloadingAttachments.contains(attKey)) return;

    if (share) {
      final rec = await FileDownloadShareHelper.getDownloadRecord(
        _attachmentRecordKey(attKey),
      );
      final savedPath = _downloadedAttachments[attKey] ?? rec?.savedPath;
      final savedName =
          _downloadedAttachmentNames[attKey] ?? rec?.fileName ?? name;
      if (savedPath != null && savedPath.isNotEmpty) {
        await FileDownloadShareHelper.shareSavedOrPrepare(
          savedPath: savedPath,
          fileName: savedName,
          mimeType: FileDownloadShareHelper.inferMimeType(savedName),
          subject: savedName,
          onPrepareShareFile: () async {
            final client = HttpClient();
            applyZjuNetworkDefense(client);
            try {
              final tempDir = Directory.systemTemp;
              final result =
                  await FileDownloadShareHelper.downloadCoursewareAndPrepareShare(
                    client,
                    item: CoursewareItem(
                      name: savedName,
                      sectionTitle: '作业附件',
                      sizeBytes: size,
                      uploadId: uploadId,
                      referenceId: referenceId,
                      directUrl: fullUrl,
                    ),
                    saveDir: tempDir.path,
                    customFileName: savedName,
                  );
              return result.shareFile;
            } finally {
              client.close(force: true);
            }
          },
        );
        return;
      }
    }

    final target = await FileDownloadShareHelper.chooseSaveTarget(
      context,
      defaultFileName: _downloadedAttachmentNames[attKey] ?? name,
      title: share ? '下载并分享作业附件' : '下载作业附件',
      confirmHint: share ? null : '仅下载保存，不会触发分享：',
    );
    if (target == null || !mounted) return;
    final saveDir = target.directory;

    setState(() {
      _downloadingAttachments.add(attKey);
    });

    final client = HttpClient();
    applyZjuNetworkDefense(client);
    try {
      final result =
          await FileDownloadShareHelper.downloadCoursewareAndPrepareShare(
            client,
            item: CoursewareItem(
              name: name,
              sectionTitle: '作业附件',
              sizeBytes: size,
              uploadId: uploadId,
              referenceId: referenceId,
              directUrl: fullUrl,
            ),
            saveDir: saveDir,
            customFileName: target.fileName,
          );
      if (!mounted) return;
      setState(() {
        _downloadingAttachments.remove(attKey);
        if (result.isSuccess) {
          _downloadedAttachments[attKey] = result.savedPath!;
          _downloadedAttachmentNames[attKey] = result.fileName;
        }
      });
      if (result.isSuccess) {
        await FileDownloadShareHelper.saveDownloadRecord(
          _attachmentRecordKey(attKey),
          savedPath: result.savedPath!,
          fileName: result.fileName,
          mimeType: result.mimeType,
        );
        AppNotification.success(
          share ? '已保存，正在分享' : '下载完成',
          '${result.fileName}\n已保存：${FileDownloadShareHelper.formatDirShort(saveDir)}',
        );
        if (share && result.shareFile != null) {
          await FileDownloadShareHelper.shareFiles(
            [result.shareFile!],
            mimeTypes: [result.mimeType],
            subject: result.fileName,
          );
        }
      } else {
        AppNotification.error('下载失败', '未能下载「$name」，请确认已登录学在浙大');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadingAttachments.remove(attKey);
        });
      }
      AppNotification.error('下载异常', '$e');
    } finally {
      client.close(force: true);
    }
  }

  /// 是否为在线小测 / 随堂测验
  bool get _isQuiz {
    if (widget.todo?.isQuiz == true) return true;
    if (widget.task?.isQuiz == true) return true;
    final type = _activityDetails?['type']?.toString().toLowerCase();
    if (type == 'quiz' ||
        type == 'exam' ||
        type == 'assessment' ||
        type == 'test') {
      return true;
    }
    final t = _resolvedTitle.toLowerCase();
    return t.contains('小测') ||
        t.contains('测验') ||
        t.contains('quiz') ||
        t.contains('随堂测') ||
        t.contains('随堂考') ||
        t.contains('在线测试') ||
        t.contains('线上测试');
  }

  List<Map<String, dynamic>> _teacherUploads = [];
  List<Map<String, dynamic>> _studentUploads = [];
  String? _teacherComment;

  // 待提交的本地附件列表与留言
  final List<Map<String, dynamic>> _selectedAttachments = [];
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmitting = false;
  double _submitProgress = 0.0;
  String? _submittingStatusText;

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
      _resolvedActivityId = widget.task!.fromUid!.substring(
        'courses-todo:'.length,
      );
    }

    // 解析 courseId 与 submitUrl
    String? rawUrl = widget.submitUrl;
    if (rawUrl == null || rawUrl.isEmpty) {
      if (widget.todo != null) {
        rawUrl = widget.todo!.submitUrl;
      } else if (widget.task != null) {
        final match = RegExp(
          r'https://courses\.zju\.edu\.cn\S+',
        ).firstMatch(widget.task!.description);
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
      final match = RegExp(
        r'/course[s]?/(\d+)/[^\d]*(\d+)',
      ).firstMatch(_resolvedSubmitUrl);
      if (match != null) {
        _resolvedCourseId = match.group(1);
        _resolvedActivityId ??= match.group(2);
      }
    }

    // 若依然未能解析出 courseId，尝试从持久化缓存的 courses_todo 匹配
    if ((_resolvedCourseId == null || _resolvedCourseId!.isEmpty) &&
        _resolvedActivityId != null) {
      try {
        if (Hive.isBoxOpen('dbOriginalWebPage')) {
          final box = Hive.box('dbOriginalWebPage');
          final cached = box.get('courses_todo');
          if (cached is String && cached.isNotEmpty) {
            final decoded = jsonDecode(cached);
            final list = asDynamicList(
              decoded is Map ? decoded['todo_list'] : null,
            );
            if (list != null) {
              for (final item in list) {
                final m = asStringMap(item);
                if (m != null && m['id']?.toString() == _resolvedActivityId) {
                  final cid = m['course_id']?.toString();
                  if (cid != null && cid.isNotEmpty) {
                    _resolvedCourseId = cid;
                    break;
                  }
                }
              }
            }
          }
        }
      } catch (_) {}
    }

    // 标题、课程名、截止时间
    if (widget.title != null && widget.title!.isNotEmpty) {
      _resolvedTitle = widget.title!;
    } else if (widget.todo != null) {
      _resolvedTitle = widget.todo!.name;
    } else if (widget.task != null) {
      _resolvedTitle = widget.task!.summary.replaceFirst(
        RegExp(r'^(作业|小测)：'),
        '',
      );
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
    applyZjuNetworkDefense(
      client,
      connectionTimeout: const Duration(seconds: 10),
    );

    try {
      // 1. 获取作业活动详情（兼容 TronClass 多租户与多路由）
      final details = await Courses.fetchActivityDetails(
        client,
        aid,
        courseId: _resolvedCourseId,
      );
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
        _teacherUploads = Courses.extractUploads(details);
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
        final createdAtStr =
            submission['created_time']?.toString() ??
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
        await _refreshAttachmentDownloadStates();
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

    // 1. 立即持久化作业/测验状态到本地 Hive 存储
    TodoTaskSync.recordHomeworkStatus(
      aid,
      completeness: submitted ? 'full' : 'incomplete',
      score: score,
      submittedAt: submitted ? (_submittedAt ?? DateTime.now()) : null,
      clearIfIncomplete: !submitted,
      isQuiz: _isQuiz,
    );

    // 2. 立即同步更新全局 Scholar todos 内存缓存，确保卡片与标签无需下拉刷新即可即时变色与变文案
    if (Get.isRegistered<Rx<Scholar>>(tag: 'scholar')) {
      final scholarRx = Get.find<Rx<Scholar>>(tag: 'scholar');
      for (final todo in scholarRx.value.todos) {
        if (todo.id == aid) {
          todo.completeness = submitted ? 'full' : 'incomplete';
          if (score != null) {
            todo.score = score;
            todo.submissionStatus = HomeworkSubmissionStatus.graded;
          } else if (submitted) {
            todo.submissionStatus = HomeworkSubmissionStatus.submitted;
            todo.submittedAt ??= DateTime.now();
          } else {
            todo.submissionStatus = HomeworkSubmissionStatus.unsubmitted;
            todo.submittedAt = null;
          }
          break;
        }
      }
      scholarRx.refresh();
    }

    // 3. 实时同步任务列表 (taskList)
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

  /// 选择本地文件作为附件（支持单选或一次多选，支持追加）
  Future<void> _pickAttachments() async {
    try {
      final pickedList = await OhosNativeService.instance.pickAnyFiles(
        maxCount: 10,
      );
      if (pickedList.isNotEmpty) {
        if (mounted) {
          setState(() {
            for (final item in pickedList) {
              final name = item['name'] as String;
              final size = item['size'] as int;
              final alreadyAdded = _selectedAttachments.any(
                (a) => a['name'] == name && a['size'] == size,
              );
              if (!alreadyAdded) {
                _selectedAttachments.add(item);
              }
            }
          });
        }
        return;
      }
    } catch (e) {
      debugPrint('pickAttachments error: $e');
    }
  }

  void _removeAttachment(int index) {
    if (index >= 0 && index < _selectedAttachments.length) {
      setState(() {
        _selectedAttachments.removeAt(index);
      });
    }
  }

  /// 提交作业流程
  Future<void> _submitHomework() async {
    final comment = _commentController.text.trim();
    if (_selectedAttachments.isEmpty && comment.isEmpty) {
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

    String confirmFileList = '';
    if (_selectedAttachments.isNotEmpty) {
      final listStr = _selectedAttachments
          .map((f) => '• ${f['name']} (${_formatFileSize(f['size'] as int)})')
          .join('\n');
      confirmFileList =
          '待上传附件 (${_selectedAttachments.length} 个)：\n$listStr\n\n';
    }

    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('确认提交作业'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text(
            '确定要向学在浙大提交此项作业吗？\n\n'
            '$confirmFileList'
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

    final hasAttachments = _selectedAttachments.isNotEmpty;
    final totalBytes = _selectedAttachments.fold<int>(0, (sum, f) {
      final b = f['bytes'] as Uint8List;
      return sum + b.length;
    });

    setState(() {
      _isSubmitting = true;
      _submitProgress = hasAttachments ? 0.03 : 0.45;
      _submittingStatusText = hasAttachments ? '准备上传附件...' : '正在向学在浙大提交作业...';
    });

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 40);
    applyZjuNetworkDefense(
      client,
      connectionTimeout: const Duration(seconds: 40),
    );

    try {
      final uploadIds = <int>[];
      var uploadedBytesBefore = 0;

      // 逐一上传所有选择的本地附件
      for (int i = 0; i < _selectedAttachments.length; i++) {
        final file = _selectedAttachments[i];
        final name = file['name'] as String;
        final bytes = file['bytes'] as Uint8List;
        var maxSentForCurrentFile = 0;

        if (mounted) {
          final initProgress = HomeworkSubmissionPage.computeUploadProgress(
            uploadedBytesBefore: uploadedBytesBefore,
            currentFileSentBytes: 0,
            currentFileTotalBytes: bytes.length,
            totalBytes: totalBytes,
            fileIndex: i,
            fileCount: _selectedAttachments.length,
          );
          setState(() {
            if (initProgress > _submitProgress) {
              _submitProgress = initProgress;
            }
            _submittingStatusText =
                '正在连接 (${i + 1}/${_selectedAttachments.length}) · $name';
          });
        }

        final uploadId = await Courses.uploadSubmissionFile(
          client,
          fileName: name,
          fileBytes: bytes,
          activityId: _resolvedActivityId,
          courseId: _resolvedCourseId,
          onProgress: (sentBytes, fileTotal) {
            if (!mounted) return;
            final clampedSent = fileTotal > 0
                ? sentBytes.clamp(0, fileTotal)
                : sentBytes;
            if (clampedSent < maxSentForCurrentFile) {
              return;
            }
            maxSentForCurrentFile = clampedSent;
            final rawProgress = HomeworkSubmissionPage.computeUploadProgress(
              uploadedBytesBefore: uploadedBytesBefore,
              currentFileSentBytes: clampedSent,
              currentFileTotalBytes: fileTotal,
              totalBytes: totalBytes,
              fileIndex: i,
              fileCount: _selectedAttachments.length,
            );
            // 严格保证进度单调递增，杜绝任何通道回退或重传导致的进度条倒退
            final nextProgress = rawProgress > _submitProgress
                ? rawProgress
                : _submitProgress;
            final String nextStatus;
            if (fileTotal > 0 && clampedSent >= fileTotal) {
              nextStatus =
                  '已上传 (${i + 1}/${_selectedAttachments.length}) · $name';
            } else if (fileTotal > 0 &&
                clampedSent >= (fileTotal * 0.90).round()) {
              nextStatus =
                  '等待确认 (${i + 1}/${_selectedAttachments.length}) · $name';
            } else if (fileTotal > 0) {
              nextStatus =
                  '上传 (${i + 1}/${_selectedAttachments.length}) ${_formatFileSize(clampedSent)}/${_formatFileSize(fileTotal)}';
            } else {
              nextStatus =
                  '正在上传 (${i + 1}/${_selectedAttachments.length}) · $name';
            }
            if ((nextProgress - _submitProgress).abs() >= 0.005 ||
                clampedSent >= fileTotal ||
                _submittingStatusText != nextStatus) {
              setState(() {
                _submitProgress = nextProgress;
                _submittingStatusText = nextStatus;
              });
            }
          },
        );
        if (uploadId != null) {
          uploadIds.add(uploadId);
          uploadedBytesBefore += bytes.length;
        } else {
          throw Exception('附件 "$name" 上传至学在浙大失败，请检查网络或在网页端提交');
        }
      }

      if (mounted) {
        setState(() {
          _submitProgress = 0.94;
          _submittingStatusText = '正在向学在浙大提交作业...';
        });
      }

      // 执行提交请求
      final success = await Courses.submitHomework(
        client,
        activityId: _resolvedActivityId!,
        courseId: _resolvedCourseId,
        uploadIds: uploadIds,
        comment: comment,
      );

      client.close(force: true);

      if (success) {
        setState(() {
          _submitProgress = 1.0;
          _submittingStatusText = '提交成功';
        });
        await Future<void>.delayed(const Duration(milliseconds: 220));
        if (mounted) {
          setState(() {
            _isSubmitting = false;
            _submitProgress = 0.0;
            _submittingStatusText = null;
            _selectedAttachments.clear();
            _commentController.clear();
          });
        }

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
        setState(() {
          _isSubmitting = false;
          _submitProgress = 0.0;
          _submittingStatusText = null;
        });
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
                  launchUrlString(
                    _resolvedSubmitUrl,
                    mode: LaunchMode.externalApplication,
                  );
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
    applyZjuNetworkDefense(
      client,
      connectionTimeout: const Duration(seconds: 15),
    );

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

  static String _decodeHtmlEntities(String text) {
    var result = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");

    result = result.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
      final code = int.tryParse(match.group(1)!);
      if (code != null) {
        try {
          return String.fromCharCode(code);
        } catch (_) {}
      }
      return match.group(0)!;
    });

    result = result.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
      final code = int.tryParse(match.group(1)!, radix: 16);
      if (code != null) {
        try {
          return String.fromCharCode(code);
        } catch (_) {}
      }
      return match.group(0)!;
    });

    return result;
  }

  static String _cleanHtmlText(String html) {
    var text = html
        .replaceAll(
          RegExp(r'<style\b[^>]*>[\s\S]*?<\/style>', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'<script\b[^>]*>[\s\S]*?<\/script>', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</div>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</tr>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</td>', caseSensitive: false), '  ')
        .replaceAll(RegExp(r'</li>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<li>', caseSensitive: false), '• ')
        .replaceAll(RegExp(r'</h[1-6]>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<[^>]*>'), '');

    text = _decodeHtmlEntities(text);
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  static List<_DescriptionSegment> _parseDescriptionSegments(String rawHtml) {
    if (rawHtml.trim().isEmpty) return [];

    final segments = <_DescriptionSegment>[];
    final imgRegex = RegExp(r'<img\b([^>]*)>', caseSensitive: false);
    final srcRegex = RegExp(
      r'''src\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    );
    final unquotedSrcRegex = RegExp(
      r'''src\s*=\s*([^\s>]+)''',
      caseSensitive: false,
    );
    final altRegex = RegExp(
      r'''alt\s*=\s*["']([^"']*)["']''',
      caseSensitive: false,
    );

    int lastIndex = 0;
    for (final match in imgRegex.allMatches(rawHtml)) {
      if (match.start > lastIndex) {
        final precedingText = _cleanHtmlText(
          rawHtml.substring(lastIndex, match.start),
        );
        if (precedingText.isNotEmpty) {
          segments.add(_TextDescriptionSegment(precedingText));
        }
      }

      final attrs = match.group(1) ?? '';
      final srcMatch =
          srcRegex.firstMatch(attrs) ?? unquotedSrcRegex.firstMatch(attrs);
      if (srcMatch != null) {
        var src = srcMatch.group(1)!.trim();
        if ((src.startsWith('"') && src.endsWith('"')) ||
            (src.startsWith("'") && src.endsWith("'"))) {
          src = src.substring(1, src.length - 1).trim();
        }
        final altMatch = altRegex.firstMatch(attrs);
        final alt = altMatch?.group(1)?.trim();

        if (src.isNotEmpty) {
          segments.add(_ImageDescriptionSegment(src: src, alt: alt));
        }
      }

      lastIndex = match.end;
    }

    if (lastIndex < rawHtml.length) {
      final tailText = _cleanHtmlText(rawHtml.substring(lastIndex));
      if (tailText.isNotEmpty) {
        segments.add(_TextDescriptionSegment(tailText));
      }
    }

    return segments;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final navTitle = _resolvedCourseName.isNotEmpty
        ? '$_resolvedCourseName · ${_isQuiz ? '在线测验' : '作业'}'
        : (_isQuiz ? '在线测试详情' : '作业详情与提交');
    return CupertinoPageScaffold(
      backgroundColor: colors.pageBg,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  AelCircleIconButton(
                    icon: AelIcons.back,
                    size: 36,
                    iconSize: 18,
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      navTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AelCircleIconButton(
                    icon: AelIcons.compass,
                    size: 36,
                    iconSize: 17,
                    tooltip: '在浏览器打开',
                    onPressed: () => launchUrlString(
                      _resolvedSubmitUrl,
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                  const SizedBox(width: 6),
                  AelCircleIconButton(
                    icon: AelIcons.refresh,
                    size: 36,
                    iconSize: 17,
                    tooltip: '刷新',
                    onPressed: _isLoading ? null : _loadData,
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CupertinoActivityIndicator(radius: 14),
                          const SizedBox(height: 12),
                          Text(
                            '正在获取学在浙大作业与提交信息...',
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        16,
                        10,
                        16,
                        MediaQuery.paddingOf(context).bottom + 24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeaderCard(colors),
                          const SizedBox(height: 12),
                          if (_errorMessage != null) ...[
                            _buildErrorCard(colors),
                            const SizedBox(height: 12),
                          ],
                          if (_isQuiz) ...[
                            _buildQuizRuleCard(colors),
                            const SizedBox(height: 12),
                          ],
                          _buildRequirementsCard(colors),
                          const SizedBox(height: 12),
                          if (_teacherUploads.isNotEmpty) ...[
                            _buildTeacherUploadsCard(colors),
                            const SizedBox(height: 12),
                          ],
                          if (_isQuiz)
                            _buildQuizConsoleSection(colors)
                          else
                            _buildSubmissionCard(colors),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuizRuleCard(AelColorTokens colors) {
    final details = _activityDetails;
    if (details == null) return const SizedBox.shrink();

    // 提取测验参数
    String? durationStr;
    final rawDuration =
        details['duration'] ?? details['time_limit'] ?? details['timelimit'];
    if (rawDuration is num && rawDuration > 0) {
      durationStr = '$rawDuration 分钟';
    } else if (rawDuration is String && rawDuration.isNotEmpty) {
      durationStr = rawDuration.contains('分') ? rawDuration : '$rawDuration 分钟';
    }

    String? attemptsStr;
    final rawAttempts =
        details['submission_count_limit'] ??
        details['allowed_attempts'] ??
        details['submit_count_limit'] ??
        details['attempt_limit'];
    if (rawAttempts is num) {
      attemptsStr = rawAttempts > 0 ? '$rawAttempts 次' : '不限次数';
    } else if (rawAttempts is String && rawAttempts.isNotEmpty) {
      attemptsStr = rawAttempts;
    }

    String? totalScoreStr;
    final rawScore =
        details['total_score'] ?? details['score'] ?? details['max_score'];
    if (rawScore is num && rawScore > 0) {
      totalScoreStr = rawScore == rawScore.roundToDouble()
          ? '${rawScore.toInt()} 分'
          : '${rawScore.toStringAsFixed(1)} 分';
    }

    String? questionsCountStr;
    final rawQCount = details['question_count'] ?? details['questions_count'];
    if (rawQCount is num && rawQCount > 0) {
      questionsCountStr = '$rawQCount 题';
    }

    return AelSectionCard(
      title: '测验规则与说明',
      icon: AelIcons.exam,
      trailing: const AelChip(label: '在线小测', tone: AelChipTone.info),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          _buildQuizParamChip(
            colors,
            icon: LucideIcons.timer,
            label: '答题限时',
            value: durationStr ?? '不限时长',
          ),
          _buildQuizParamChip(
            colors,
            icon: AelIcons.refresh,
            label: '允许次数',
            value: attemptsStr ?? '1 次',
          ),
          if (totalScoreStr != null)
            _buildQuizParamChip(
              colors,
              icon: AelIcons.award,
              label: '测验满分',
              value: totalScoreStr,
            ),
          if (questionsCountStr != null)
            _buildQuizParamChip(
              colors,
              icon: LucideIcons.hash,
              label: '题目数量',
              value: questionsCountStr,
            ),
        ],
      ),
    );
  }

  Widget _buildQuizParamChip(
    AelColorTokens colors, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.infoContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colors.onInfoContainer),
          const SizedBox(width: 5),
          Text(
            '$label: ',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: colors.onInfoContainer,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuizConsoleSection(AelColorTokens colors) {
    return AelSectionCard(
      title: _isSubmitted ? '测验完成记录' : '在线测验作答',
      icon: _isSubmitted ? AelIcons.success : AelIcons.edit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isSubmitted) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.successContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(AelIcons.check, size: 16, color: colors.success),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _submittedAt != null
                              ? '已于 ${_submittedAt!.year}-${_submittedAt!.month.toString().padLeft(2, '0')}-${_submittedAt!.day.toString().padLeft(2, '0')} ${_submittedAt!.hour.toString().padLeft(2, '0')}:${_submittedAt!.minute.toString().padLeft(2, '0')} 完成作答'
                              : '已在学在浙大完成测验作答',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.onSuccessContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_score != null) ...[
                    const SizedBox(height: 8),
                    AelChip(
                      leadingIcon: AelIcons.award,
                      label:
                          '测验得分：${_score == _score!.roundToDouble() ? _score!.toInt() : _score!.toStringAsFixed(1)} 分',
                      tone: AelChipTone.warning,
                    ),
                  ],
                  if (_teacherComment != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '教师评语：$_teacherComment',
                      style: TextStyle(fontSize: 12, color: colors.textPrimary),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.infoContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(AelIcons.info, size: 16, color: colors.onInfoContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '在线小测/随堂测试需在学在浙大在线答题系统完成。请点击下方“进入在线作答”在浏览器中完成试题。答题完毕后，点击“探测作答与得分”即可一键同步。',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: colors.onInfoContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // 核心作答按钮
          AelButton(
            expanded: true,
            icon: AelIcons.externalLink,
            label: _isSubmitted ? '在网页端查看答卷与解析' : '进入学在浙大在线作答',
            onPressed: () => launchUrlString(
              _resolvedSubmitUrl,
              mode: LaunchMode.externalApplication,
            ),
          ),
          const SizedBox(height: 10),

          // 探测与辅助按钮行
          Row(
            children: [
              Expanded(
                child: AelButton(
                  variant: AelButtonVariant.tonal,
                  icon: AelIcons.search,
                  label: '探测作答与得分',
                  onPressed: _isLoading ? null : _loadData,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AelButton(
                  variant: _isSubmitted
                      ? AelButtonVariant.destructive
                      : AelButtonVariant.tonal,
                  icon: _isSubmitted ? AelIcons.close : AelIcons.check,
                  label: _isSubmitted ? '标记为未作答' : '手动标记已作答',
                  onPressed: () {
                    final targetSubmitted = !_isSubmitted;
                    setState(() {
                      _isSubmitted = targetSubmitted;
                      if (targetSubmitted) {
                        _submittedAt ??= DateTime.now();
                      }
                    });
                    _syncTaskStatusLocally(targetSubmitted, _score);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AelButton(
            expanded: true,
            variant: AelButtonVariant.tonal,
            icon: AelIcons.copy,
            label: '复制作答直达链接',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _resolvedSubmitUrl));
              showCupertinoDialog<void>(
                context: context,
                builder: (ctx) => CupertinoAlertDialog(
                  title: const Text('已复制作答链接'),
                  content: const Padding(
                    padding: EdgeInsets.only(top: 8.0),
                    child: Text('测验作答链接已复制到剪贴板，您可以发送到电脑端或平板端浏览器中作答。'),
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
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(AelColorTokens colors) {
    final now = DateTime.now();
    final isGraded = _score != null;
    final isOverdue =
        !_isSubmitted &&
        _resolvedEndTime != null &&
        _resolvedEndTime!.isBefore(now);

    AelChipTone badgeTone;
    IconData badgeIcon;
    String badgeText;

    if (isGraded) {
      badgeTone = AelChipTone.warning;
      badgeIcon = AelIcons.award;
      final sText = _score == _score!.roundToDouble()
          ? _score!.toInt().toString()
          : _score!.toStringAsFixed(1);
      badgeText = '已批改 · $sText 分';
    } else if (_isSubmitted) {
      badgeTone = AelChipTone.success;
      badgeIcon = AelIcons.success;
      badgeText = _isQuiz ? '已作答（待批改）' : '已提交（待批改）';
    } else if (isOverdue) {
      badgeTone = AelChipTone.error;
      badgeIcon = AelIcons.error;
      badgeText = _isQuiz ? '已逾期未测' : '已逾期';
    } else {
      if (_isQuiz) {
        badgeTone = AelChipTone.info;
        badgeIcon = AelIcons.edit;
        badgeText = '待作答';
      } else {
        badgeTone = AelChipTone.primary;
        badgeIcon = AelIcons.tabFlow;
        badgeText = '待提交';
      }
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

    return AelSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isQuiz) ...[
            const AelChip(
              leadingIcon: AelIcons.edit,
              label: '随堂测验 / 在线小测',
              tone: AelChipTone.info,
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  _resolvedTitle,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AelChip(
                leadingIcon: badgeIcon,
                label: badgeText,
                tone: badgeTone,
              ),
            ],
          ),
          if (_resolvedCourseName.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '课程：$_resolvedCourseName',
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            ddlStr,
            style: TextStyle(
              fontSize: 12,
              color: isOverdue ? colors.error : colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(AelColorTokens colors) {
    return AelSectionCard(
      backgroundColor: colors.warningContainer,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AelIcons.warning, size: 20, color: colors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage ?? '',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: colors.onWarningContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequirementsCard(AelColorTokens colors) {
    final rawDesc = Courses.extractDescription(_activityDetails);
    final segments = _parseDescriptionSegments(rawDesc);

    return AelSectionCard(
      title: '作业要求与说明',
      icon: AelIcons.file,
      trailing: segments.any((s) => s is _ImageDescriptionSegment)
          ? const AelChip(label: '含图', tone: AelChipTone.primary)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (segments.isNotEmpty) ...[
            ...segments.asMap().entries.map((entry) {
              final idx = entry.key;
              final seg = entry.value;
              final isLast = idx == segments.length - 1;
              if (seg is _TextDescriptionSegment) {
                return Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 8.0),
                  child: SelectableText(
                    seg.text,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: colors.textPrimary,
                    ),
                  ),
                );
              } else if (seg is _ImageDescriptionSegment) {
                return Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 8.0),
                  child: _CoursesNetworkImage(url: seg.src, alt: seg.alt),
                );
              }
              return const SizedBox.shrink();
            }),
          ] else ...[
            Text(
              _teacherUploads.isNotEmpty
                  ? '教师未填写文本说明，请查阅下方附件。'
                  : '教师未填写作业补充说明。',
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: colors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _attachmentPill({
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12.5, color: fg),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTeacherUploadsCard(AelColorTokens colors) {
    return AelSectionCard(
      title: '教师附件 (${_teacherUploads.length})',
      icon: LucideIcons.paperclip,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._teacherUploads.map((file) {
            final name = file['name']?.toString() ?? '附件文件';
            final size = (file['size'] as num?)?.toInt() ?? 0;
            final uploadId = (file['id'] as num?)?.toInt() ?? 0;
            final referenceId = (file['reference_id'] as num?)?.toInt() ?? 0;
            final downloadUrl =
                file['download_url']?.toString() ??
                '/api/uploads/${file['id']}/blob';
            final fullUrl = downloadUrl.startsWith('http')
                ? downloadUrl
                : 'https://courses.zju.edu.cn$downloadUrl';
            final attKey = '${uploadId}_${referenceId}_$fullUrl';
            final isDownloading = _downloadingAttachments.contains(attKey);
            final isDownloaded = _downloadedAttachments.containsKey(attKey);

            final isImage =
                RegExp(
                  r'\.(png|jpe?g|gif|webp|bmp)$',
                  caseSensitive: false,
                ).hasMatch(name) ||
                (file['content_type']?.toString().toLowerCase().startsWith(
                      'image/',
                    ) ??
                    false);

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.tonalTileBg,
                  borderRadius: BorderRadius.circular(AelRadius.tile),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isImage ? AelIcons.image : AelIcons.file,
                          size: 20,
                          color: isImage ? colors.info : colors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: colors.textPrimary,
                                ),
                              ),
                              if (size > 0)
                                Text(
                                  _formatFileSize(size),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (isDownloading)
                          const CupertinoActivityIndicator(radius: 8)
                        else ...[
                          if (isImage) ...[
                            _attachmentPill(
                              icon: AelIcons.search,
                              label: '预览',
                              bg: colors.infoContainer,
                              fg: colors.onInfoContainer,
                              onTap: () {
                                Navigator.of(context).push(
                                  CupertinoPageRoute(
                                    builder: (ctx) => _CoursesImageViewerPage(
                                      imageUrl: fullUrl,
                                      title: name,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 4),
                          ],
                          _attachmentPill(
                            icon: isDownloaded
                                ? AelIcons.check
                                : AelIcons.download,
                            label: isDownloaded ? '已下载' : '下载',
                            bg: isDownloaded
                                ? colors.successContainer
                                : colors.primaryContainer,
                            fg: isDownloaded
                                ? colors.onSuccessContainer
                                : colors.onPrimaryContainer,
                            onTap: () => _downloadOrShareAttachment(
                              attKey: attKey,
                              name: name,
                              fullUrl: fullUrl,
                              size: size,
                              uploadId: uploadId,
                              referenceId: referenceId,
                              share: false,
                            ),
                          ),
                          const SizedBox(width: 4),
                          _attachmentPill(
                            icon: AelIcons.share,
                            label: '分享',
                            bg: colors.cardBg,
                            fg: colors.textPrimary,
                            onTap: () => _downloadOrShareAttachment(
                              attKey: attKey,
                              name: name,
                              fullUrl: fullUrl,
                              size: size,
                              uploadId: uploadId,
                              referenceId: referenceId,
                              share: true,
                            ),
                          ),
                        ],
                      ],
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

  Widget _buildSubmissionCard(AelColorTokens colors) {
    return AelSectionCard(
      title: _isSubmitted ? '提交记录' : '作业提交',
      icon: _isSubmitted ? AelIcons.success : AelIcons.upload,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 若已提交：展示提交详情与撤回选项
          if (_isSubmitted) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.successContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(AelIcons.check, size: 16, color: colors.success),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _submittedAt != null
                              ? '已于 ${_submittedAt!.year}-${_submittedAt!.month.toString().padLeft(2, '0')}-${_submittedAt!.day.toString().padLeft(2, '0')} ${_submittedAt!.hour.toString().padLeft(2, '0')}:${_submittedAt!.minute.toString().padLeft(2, '0')} 提交'
                              : '已在学在浙大完成提交',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.onSuccessContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_studentUploads.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '已提交附件：',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ..._studentUploads.map((file) {
                      final name = file['name']?.toString() ?? '提交文件';
                      final size = (file['size'] as num?)?.toInt() ?? 0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Row(
                          children: [
                            Icon(
                              LucideIcons.paperclip,
                              size: 14,
                              color: colors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '$name (${size > 0 ? _formatFileSize(size) : "已上传"})',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textPrimary,
                                ),
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
                      style: TextStyle(fontSize: 12, color: colors.textPrimary),
                    ),
                  ],
                  if (_teacherComment != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colors.warningContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '教师评语：$_teacherComment',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onWarningContainer,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_allowRetract && _score == null) ...[
              AelButton(
                expanded: true,
                variant: AelButtonVariant.destructive,
                icon: _isSubmitting ? null : AelIcons.refresh,
                label: _isSubmitting ? '正在撤回...' : '撤回作业提交',
                onPressed: _isSubmitting ? null : _retractHomework,
              ),
            ],
          ] else ...[
            // 未提交：文件选择器与提交留言
            if (_selectedAttachments.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '待提交附件 (${_selectedAttachments.length})',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  AelChip(
                    label: '清空',
                    tone: AelChipTone.error,
                    onTap: () {
                      setState(() {
                        _selectedAttachments.clear();
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ..._selectedAttachments.asMap().entries.map((entry) {
                final idx = entry.key;
                final file = entry.value;
                final name = file['name']?.toString() ?? '待提交文件';
                final size = (file['size'] as num?)?.toInt() ?? 0;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colors.tonalTileBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(AelIcons.file, size: 20, color: colors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textPrimary,
                                ),
                              ),
                              if (size > 0)
                                Text(
                                  _formatFileSize(size),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        CupertinoButton(
                          padding: const EdgeInsets.all(4),
                          minimumSize: Size.zero,
                          onPressed: () => _removeAttachment(idx),
                          child: Icon(
                            AelIcons.close,
                            size: 18,
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 6),
            ],

            AelButton(
              expanded: true,
              variant: AelButtonVariant.tonal,
              icon: LucideIcons.paperclip,
              label: _selectedAttachments.isEmpty ? '选择文件附件（支持多选）' : '继续添加附件',
              onPressed: _isSubmitting ? null : _pickAttachments,
            ),
            const SizedBox(height: 10),

            CupertinoTextField(
              controller: _commentController,
              placeholder: '给教师的留言或作业文字说明（可选）',
              maxLines: 3,
              padding: const EdgeInsets.all(10),
              style: TextStyle(color: colors.textPrimary),
              placeholderStyle: TextStyle(color: colors.textTertiary),
              decoration: BoxDecoration(
                color: colors.tonalTileBg,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 12),

            _buildSubmitButton(context, colors),
          ],
        ],
      ),
    );
  }

  Widget _buildSubmitButton(BuildContext context, AelColorTokens colors) {
    if (!_isSubmitting) {
      return AelButton(
        expanded: true,
        icon: AelIcons.upload,
        label: _selectedAttachments.isNotEmpty
            ? '提交作业 (${_selectedAttachments.length} 个附件)'
            : '提交作业',
        onPressed: _submitHomework,
      );
    }

    final statusLabel = _submittingStatusText ?? '正在提交作业...';

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(end: _submitProgress.clamp(0.0, 1.0)),
      builder: (context, progress, _) {
        final pctText = '${(progress * 100).round()}%';
        final isCompletedStage = progress >= 0.999;

        Widget buildContent(Color foreground, {bool animateSpinner = true}) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isCompletedStage)
                  Icon(AelIcons.success, size: 16, color: foreground)
                else
                  CupertinoActivityIndicator(
                    radius: 7.5,
                    color: foreground,
                    animating: animateSpinner,
                  ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    statusLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  pctText,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: foreground,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(AelRadius.button),
          child: SizedBox(
            width: double.infinity,
            height: 44,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(AelRadius.button),
                  ),
                  alignment: Alignment.center,
                  child: buildContent(
                    colors.onPrimaryContainer,
                    animateSpinner: true,
                  ),
                ),
                ClipRect(
                  clipper: _HorizontalFractionClipper(progress),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isCompletedStage ? colors.success : colors.primary,
                    ),
                    alignment: Alignment.center,
                    child: buildContent(colors.onPrimary, animateSpinner: true),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HorizontalFractionClipper extends CustomClipper<Rect> {
  final double fraction;

  _HorizontalFractionClipper(this.fraction);

  @override
  Rect getClip(Size size) {
    final width = (size.width * fraction.clamp(0.0, 1.0));
    return Rect.fromLTWH(0, 0, width, size.height);
  }

  @override
  bool shouldReclip(covariant _HorizontalFractionClipper oldClipper) {
    return oldClipper.fraction != fraction;
  }
}

abstract class _DescriptionSegment {}

class _TextDescriptionSegment extends _DescriptionSegment {
  final String text;
  _TextDescriptionSegment(this.text);
}

class _ImageDescriptionSegment extends _DescriptionSegment {
  final String src;
  final String? alt;
  _ImageDescriptionSegment({required this.src, this.alt});
}

/// 支持 TronClass 会话鉴权、防重定向拦截与内存缓存的图片组件
class _CoursesNetworkImage extends StatefulWidget {
  final String url;
  final String? alt;

  const _CoursesNetworkImage({required this.url, this.alt});

  static final Map<String, Uint8List> _imageCache = <String, Uint8List>{};

  @override
  State<_CoursesNetworkImage> createState() => _CoursesNetworkImageState();
}

class _CoursesNetworkImageState extends State<_CoursesNetworkImage> {
  Uint8List? _bytes;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant _CoursesNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    final rawUrl = widget.url.trim();
    if (rawUrl.isEmpty) {
      setState(() => _error = '图片地址为空');
      return;
    }

    // Base64 data URL 处理
    if (rawUrl.startsWith('data:image')) {
      final comma = rawUrl.indexOf(',');
      if (comma != -1) {
        try {
          final data = base64Decode(rawUrl.substring(comma + 1));
          setState(() {
            _bytes = data;
            _isLoading = false;
            _error = null;
          });
          return;
        } catch (_) {
          setState(() => _error = 'Base64 图片解析失败');
          return;
        }
      }
    }

    // 内存缓存检查
    if (_CoursesNetworkImage._imageCache.containsKey(rawUrl)) {
      setState(() {
        _bytes = _CoursesNetworkImage._imageCache[rawUrl];
        _isLoading = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final fullUrl = rawUrl.startsWith('http')
        ? rawUrl
        : 'https://courses.zju.edu.cn${rawUrl.startsWith('/') ? '' : '/'}$rawUrl';

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    applyZjuNetworkDefense(
      client,
      connectionTimeout: const Duration(seconds: 10),
    );

    try {
      var currentUri = Uri.parse(fullUrl);
      var session = Courses.cachedSession;
      if (session == null &&
          (currentUri.host.isEmpty || currentUri.host.endsWith('zju.edu.cn'))) {
        session = await Courses.ensureSession(client);
      }

      int redirects = 0;
      HttpClientResponse? response;
      while (redirects < 5) {
        final req = await client
            .getUrl(currentUri)
            .timeout(const Duration(seconds: 12));
        req.followRedirects = false;
        if (session != null &&
            (currentUri.host == 'courses.zju.edu.cn' ||
                currentUri.host.endsWith('.zju.edu.cn'))) {
          req.cookies.add(session);
        }
        response = await req.close().timeout(const Duration(seconds: 12));
        if (response.isRedirect) {
          final loc = response.headers.value(HttpHeaders.locationHeader);
          if (loc != null && loc.isNotEmpty) {
            currentUri = currentUri.resolve(loc);
            redirects++;
            continue;
          }
        }
        break;
      }

      if (response != null && response.statusCode == HttpStatus.ok) {
        final data = await consolidateHttpClientResponseBytes(response);
        if (mounted) {
          _CoursesNetworkImage._imageCache[rawUrl] = data;
          setState(() {
            _bytes = data;
            _isLoading = false;
            _error = null;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = '图片加载失败 (HTTP ${response?.statusCode ?? 0})';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '网络错误: $e';
        });
      }
    } finally {
      client.close(force: true);
    }
  }

  void _openViewer() {
    if (_bytes == null && (_error != null || _isLoading)) return;
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (ctx) => _CoursesImageViewerPage(
          imageBytes: _bytes,
          imageUrl: widget.url,
          title: widget.alt?.isNotEmpty == true ? widget.alt! : '作业说明插图',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    if (_isLoading) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.tonalTileBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CupertinoActivityIndicator(radius: 12),
            const SizedBox(height: 8),
            Text(
              '正在加载说明插图...',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_error != null || _bytes == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.tonalTileBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(AelIcons.image, size: 20, color: colors.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.alt?.isNotEmpty == true
                    ? '${widget.alt} (图片加载失败)'
                    : (_error ?? '图片无法加载'),
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ),
            AelChip(label: '重试', tone: AelChipTone.primary, onTap: _loadImage),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _openViewer,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              constraints: const BoxConstraints(maxHeight: 320),
              width: double.infinity,
              color: colors.tonalTileBg,
              child: Image.memory(_bytes!, fit: BoxFit.contain),
            ),
            Container(
              margin: const EdgeInsets.all(6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AelSemanticPalette.pureBlack.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    AelIcons.search,
                    color: AelSemanticPalette.pureWhite,
                    size: 12,
                  ),
                  SizedBox(width: 3),
                  Text(
                    '点击放大',
                    style: TextStyle(
                      color: AelSemanticPalette.pureWhite,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 图片全屏查看器，支持多指手势缩放与拖拽查看
class _CoursesImageViewerPage extends StatefulWidget {
  final Uint8List? imageBytes;
  final String? imageUrl;
  final String title;

  const _CoursesImageViewerPage({
    this.imageBytes,
    this.imageUrl,
    required this.title,
  });

  @override
  State<_CoursesImageViewerPage> createState() =>
      _CoursesImageViewerPageState();
}

class _CoursesImageViewerPageState extends State<_CoursesImageViewerPage> {
  Uint8List? _bytes;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bytes = widget.imageBytes;
    if (_bytes == null &&
        widget.imageUrl != null &&
        widget.imageUrl!.isNotEmpty) {
      _fetchImage();
    }
  }

  Future<void> _fetchImage() async {
    final rawUrl = widget.imageUrl!.trim();
    if (_CoursesNetworkImage._imageCache.containsKey(rawUrl)) {
      setState(() => _bytes = _CoursesNetworkImage._imageCache[rawUrl]);
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final fullUrl = rawUrl.startsWith('http')
        ? rawUrl
        : 'https://courses.zju.edu.cn${rawUrl.startsWith('/') ? '' : '/'}$rawUrl';

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    applyZjuNetworkDefense(
      client,
      connectionTimeout: const Duration(seconds: 12),
    );

    try {
      var currentUri = Uri.parse(fullUrl);
      var session = Courses.cachedSession;
      if (session == null &&
          (currentUri.host.isEmpty || currentUri.host.endsWith('zju.edu.cn'))) {
        session = await Courses.ensureSession(client);
      }

      int redirects = 0;
      HttpClientResponse? response;
      while (redirects < 5) {
        final req = await client
            .getUrl(currentUri)
            .timeout(const Duration(seconds: 12));
        req.followRedirects = false;
        if (session != null &&
            (currentUri.host == 'courses.zju.edu.cn' ||
                currentUri.host.endsWith('.zju.edu.cn'))) {
          req.cookies.add(session);
        }
        response = await req.close().timeout(const Duration(seconds: 12));
        if (response.isRedirect) {
          final loc = response.headers.value(HttpHeaders.locationHeader);
          if (loc != null && loc.isNotEmpty) {
            currentUri = currentUri.resolve(loc);
            redirects++;
            continue;
          }
        }
        break;
      }

      if (response != null && response.statusCode == HttpStatus.ok) {
        final data = await consolidateHttpClientResponseBytes(response);
        if (mounted) {
          _CoursesNetworkImage._imageCache[rawUrl] = data;
          setState(() {
            _bytes = data;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = '图片加载失败 (HTTP ${response?.statusCode ?? 0})';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '$e';
        });
      }
    } finally {
      client.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fullUrl = widget.imageUrl != null && widget.imageUrl!.isNotEmpty
        ? (widget.imageUrl!.startsWith('http')
              ? widget.imageUrl!
              : 'https://courses.zju.edu.cn${widget.imageUrl!.startsWith('/') ? '' : '/'}${widget.imageUrl!}')
        : null;

    final colors = AelTheme.colorsOf(context);
    return CupertinoPageScaffold(
      backgroundColor: AelSemanticPalette.pureBlack,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: AelSemanticPalette.pureBlack.withValues(alpha: 0.7),
        middle: Text(
          widget.title,
          style: const TextStyle(
            color: AelSemanticPalette.pureWhite,
            fontSize: 16,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Icon(
            AelIcons.close,
            color: AelSemanticPalette.pureWhite,
            size: 20,
          ),
        ),
        trailing: fullUrl != null
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: () => launchUrlString(
                  fullUrl,
                  mode: LaunchMode.externalApplication,
                ),
                child: const Icon(
                  AelIcons.compass,
                  color: AelSemanticPalette.pureWhite,
                  size: 20,
                ),
              )
            : null,
      ),
      child: SafeArea(
        child: Center(
          child: _isLoading
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CupertinoActivityIndicator(
                      radius: 14,
                      color: AelSemanticPalette.pureWhite,
                    ),
                    SizedBox(height: 12),
                    Text(
                      '正在加载完整图片...',
                      style: TextStyle(
                        color: AelSemanticPalette.pureWhite,
                        fontSize: 13,
                      ),
                    ),
                  ],
                )
              : _error != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(AelIcons.warning, color: colors.warning, size: 36),
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: AelSemanticPalette.pureWhite,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AelButton(label: '重试', onPressed: _fetchImage),
                  ],
                )
              : _bytes != null && _bytes!.isNotEmpty
              ? InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 6.0,
                  child: Center(
                    child: Image.memory(_bytes!, fit: BoxFit.contain),
                  ),
                )
              : const Text(
                  '暂无图片数据',
                  style: TextStyle(color: AelSemanticPalette.pureWhite),
                ),
        ),
      ),
    );
  }
}
