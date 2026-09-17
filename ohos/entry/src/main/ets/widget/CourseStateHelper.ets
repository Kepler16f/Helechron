import preferences from '@ohos.data.preferences';
import { BusinessError } from '@kit.BasicServicesKit';
import { formProvider } from '@kit.FormKit';

const DEFAULT_LEAD_MINUTES = 120;
const COLOR_ONGOING = '#4CAF50';
const COLOR_SOON = '#2196F3';
const COLOR_URGENT = '#FF9800';
const COLOR_IDLE = '#888888';
const COLOR_PROGRESS_DEFAULT = '#1E88E5';
const MIN_NEXT_REFRESH_MINUTES = 5;

export interface CourseState {
  status: string;
  statusColor: string;
  countdown: string;
  progress: string;
  progressColor: string;
  hasCourse: string;
}

function getStr(prefs: preferences.Preferences, key: string, def: string): string {
  const v = prefs.getSync(key, def);
  return typeof v === 'string' ? v : def;
}

function getNum(prefs: preferences.Preferences, key: string, def: number): number {
  const v = prefs.getSync(key, def);
  return typeof v === 'number' ? v : def;
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

/// 依据课程起止时间戳与当前时间计算状态、倒计时与进度。
/// 全部在原生侧完成，因此系统级刷新（定时/下次刷新）无需 Dart 参与。
export function computeCourseState(prefs: preferences.Preferences): CourseState {
  const hasCourse = getStr(prefs, 'hasCourse', '0');
  const startMs = getNum(prefs, 'courseStartMs', 0);
  const endMs = getNum(prefs, 'courseEndMs', 0);
  let leadMin = getNum(prefs, 'leadWindowMinutes', DEFAULT_LEAD_MINUTES);
  if (leadMin <= 0) {
    leadMin = DEFAULT_LEAD_MINUTES;
  }

  if (hasCourse !== '1' || startMs <= 0 || endMs <= 0) {
    const idle: CourseState = {
      status: '全部结课',
      statusColor: COLOR_IDLE,
      countdown: '',
      progress: '0',
      progressColor: COLOR_PROGRESS_DEFAULT,
      hasCourse: '0'
    };
    return idle;
  }

  const now = Date.now();
  let status = '';
  let statusColor = COLOR_SOON;
  let progress = 0;
  let countdown = '';

  if (now >= startMs && now < endMs) {
    const total = endMs - startMs;
    const elapsed = now - startMs;
    progress = total <= 0 ? 100 : (elapsed / total) * 100;
    status = '上课中';
    statusColor = COLOR_ONGOING;
    const remainMin = Math.floor((endMs - now) / 60000);
    countdown = `${pad2(Math.floor(remainMin / 60))}:${pad2(remainMin % 60)}`;
  } else {
    const remainMin = Math.floor((startMs - now) / 60000);
    if (remainMin >= leadMin) {
      progress = 0;
    } else if (remainMin <= 0) {
      progress = 100;
    } else {
      progress = (1 - remainMin / leadMin) * 100;
    }
    if (remainMin <= 0) {
      status = '即将开始';
      statusColor = COLOR_SOON;
    } else if (remainMin < 60) {
      status = `开始还有 ${remainMin} 分钟`;
      statusColor = remainMin <= 30 ? COLOR_URGENT : COLOR_SOON;
    } else {
      const h = Math.floor(remainMin / 60);
      const m = remainMin % 60;
      status = m > 0 ? `开始还有 ${h} 小时 ${m} 分` : `开始还有 ${h} 小时`;
      statusColor = COLOR_SOON;
    }
    countdown = `${pad2(Math.floor(remainMin / 60))}:${pad2(remainMin % 60)}`;
  }

  if (progress < 0) {
    progress = 0;
  }
  if (progress > 100) {
    progress = 100;
  }

  const result: CourseState = {
    status: status,
    statusColor: statusColor,
    countdown: countdown,
    progress: Math.round(progress).toString(),
    progressColor: statusColor,
    hasCourse: '1'
  };
  return result;
}

/// 构造可下发给卡片页面的完整数据。
export function buildCourseFormData(prefs: preferences.Preferences): Record<string, string> {
  const state = computeCourseState(prefs);
  const data: Record<string, string> = {
    'courseName': getStr(prefs, 'courseName', '今日暂无课程'),
    'courseTime': getStr(prefs, 'courseTime', ''),
    'courseLocation': getStr(prefs, 'courseLocation', ''),
    'courseTeacher': getStr(prefs, 'courseTeacher', ''),
    'courseStatus': state.status,
    'courseStatusColor': state.statusColor,
    'courseStatusTime': state.countdown,
    'progressPercent': state.progress,
    'progressColor': state.progressColor,
    'hasCourse': state.hasCourse
  };
  return data;
}

/// 距离下一个课程边界（开课/下课）的分钟数，用于 setFormNextRefreshTime。
/// 返回 0 表示无需调度；最小值受系统限制为 5 分钟。
export function minutesToNextBoundary(prefs: preferences.Preferences): number {
  const startMs = getNum(prefs, 'courseStartMs', 0);
  const endMs = getNum(prefs, 'courseEndMs', 0);
  if (startMs <= 0 || endMs <= 0) {
    return 0;
  }
  const now = Date.now();
  let boundary = 0;
  if (now < startMs) {
    boundary = startMs;
  } else if (now < endMs) {
    boundary = endMs;
  } else {
    return 0;
  }
  let minutes = Math.ceil((boundary - now) / 60000);
  if (minutes < MIN_NEXT_REFRESH_MINUTES) {
    minutes = MIN_NEXT_REFRESH_MINUTES;
  }
  return minutes;
}

/// 为单个卡片调度下一次系统刷新（在课程边界处切换课程）。
export function scheduleBoundaryRefresh(formId: string, prefs: preferences.Preferences): void {
  const minutes = minutesToNextBoundary(prefs);
  if (minutes <= 0) {
    return;
  }
  try {
    formProvider.setFormNextRefreshTime(formId, minutes, (err: BusinessError) => {
      if (err) {
        console.warn(`setFormNextRefreshTime failed: ${err.code} ${err.message}`);
      }
    });
  } catch (e) {
    console.warn(`setFormNextRefreshTime exception: ${JSON.stringify(e)}`);
  }
}
