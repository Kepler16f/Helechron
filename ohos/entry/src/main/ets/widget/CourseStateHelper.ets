import preferences from '@ohos.data.preferences';
import { BusinessError } from '@kit.BasicServicesKit';
import { formProvider } from '@kit.FormKit';

const DEFAULT_LEAD_MINUTES = 120;
const COLOR_ONGOING = '#4CAF50';
const COLOR_SOON = '#2196F3';
const COLOR_URGENT = '#FF9800';
const COLOR_IDLE = '#888888';
const COLOR_PROGRESS_DEFAULT = '#1E88E5';

/// 系统"下次刷新"最小间隔（分钟），由系统限制
const MIN_NEXT_REFRESH_MINUTES = 5;
/// 每个课程边界调度的提前量（分钟），确保不晚于边界触发
const BOUNDARY_LEAD_MINUTES = 1;
/// 单次可调度的最长等待（分钟），超过则交由定时刷新兜底
const MAX_NEXT_REFRESH_MINUTES = 60 * 24;

export interface CourseItem {
  s: number; // 开始时间戳(ms)
  e: number; // 结束时间戳(ms)
  n: string; // 课程名
  t: string; // 时间区间
  l: string; // 地点
  c: string; // 教师
}

export interface CourseState {
  status: string;
  statusColor: string;
  countdown: string;
  progress: string;
  progressColor: string;
  hasCourse: string;
  name: string;
  time: string;
  location: string;
  teacher: string;
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

/// 解析 Dart 侧下发的课程时间表。
function parseCourses(prefs: preferences.Preferences): CourseItem[] {
  const json = getStr(prefs, 'coursesJson', '');
  const items: CourseItem[] = [];
  if (json.length === 0) {
    return items;
  }
  try {
    const raw = JSON.parse(json) as Record<string, Object>[];
    for (const r of raw) {
      const s = r['s'];
      const e = r['e'];
      const n = r['n'];
      const t = r['t'];
      const l = r['l'];
      const c = r['c'];
      const item: CourseItem = {
        s: typeof s === 'number' ? s : 0,
        e: typeof e === 'number' ? e : 0,
        n: typeof n === 'string' ? n : '',
        t: typeof t === 'string' ? t : '',
        l: typeof l === 'string' ? l : '',
        c: typeof c === 'string' ? c : ''
      };
      if (item.e > 0) {
        items.push(item);
      }
    }
  } catch (err) {
    console.error(`parseCourses failed: ${JSON.stringify(err)}`);
  }
  return items;
}

/// 选取当前进行中或最近将要开始的课程（结束时间晚于现在的、开始最早的一节）。
function pickCurrentOrNext(items: CourseItem[], now: number): CourseItem | null {
  let best: CourseItem | null = null;
  for (const item of items) {
    if (item.e <= now) {
      continue;
    }
    if (best === null || item.s < best.s) {
      best = item;
    }
  }
  return best;
}

function idleState(): CourseState {
  const idle: CourseState = {
    status: '全部结课',
    statusColor: COLOR_IDLE,
    countdown: '',
    progress: '0',
    progressColor: COLOR_PROGRESS_DEFAULT,
    hasCourse: '0',
    name: '今日暂无课程',
    time: '',
    location: '',
    teacher: ''
  };
  return idle;
}

/// 依据课程时间表与当前时间计算状态、倒计时与进度。
export function computeCourseState(prefs: preferences.Preferences): CourseState {
  const items = parseCourses(prefs);
  const leadMin = getNum(prefs, 'leadWindowMinutes', DEFAULT_LEAD_MINUTES);
  const now = Date.now();
  const item = pickCurrentOrNext(items, now);
  if (item === null) {
    return idleState();
  }

  // 读取精度模式：'exact'=精确(时:分)，'coarse'=粗略(30分钟粒度)
  const precision = getStr(prefs, 'widgetPrecision', 'exact');

  let status = '';
  let statusColor = COLOR_SOON;
  let progress = 0;
  let countdown = '';

  if (now >= item.s && now < item.e) {
    // 上课中
    const total = item.e - item.s;
    const elapsed = now - item.s;
    progress = total <= 0 ? 100 : (elapsed / total) * 100;
    status = '上课中';
    statusColor = COLOR_ONGOING;
    const remainMs = item.e - now;
    if (precision === 'coarse') {
      // 粗略模式：按 30 分钟粒度
      const remainMin = Math.round(remainMs / 60000 / 30) * 30;
      countdown = `${pad2(Math.floor(remainMin / 60))}:${pad2(remainMin % 60)}`;
    } else {
      // 精确模式：精确到分
      const remainMin = Math.floor(remainMs / 60000);
      countdown = `${pad2(Math.floor(remainMin / 60))}:${pad2(remainMin % 60)}`;
    }
  } else {
    // 开课前
    const remainMs = item.s - now;
    const remainMin = Math.floor(remainMs / 60000);

    // 进度条：距开课 >2h 隐藏，≤2h 线性渐进
    if (remainMin > leadMin) {
      progress = 0;
    } else if (remainMin <= 0) {
      progress = 100;
    } else {
      progress = (1 - remainMin / leadMin) * 100;
    }

    if (remainMin <= 0) {
      status = '即将开始';
      statusColor = COLOR_SOON;
    } else {
      // 倒计时文本：始终显示"开始还有 X 时 X 分"，不再重复 HH:MM
      if (precision === 'coarse') {
        // 粗略模式：按 30 分钟粒度
        const rounded = Math.round(remainMin / 30) * 30;
        const h = Math.floor(rounded / 60);
        const m = rounded % 60;
        status = m > 0 ? `开始还有 ${h} 小时 ${m} 分` : `开始还有 ${h} 小时`;
      } else {
        // 精确模式
        const h = Math.floor(remainMin / 60);
        const m = remainMin % 60;
        status = m > 0 ? `开始还有 ${h} 小时 ${m} 分` : `开始还有 ${h} 小时`;
      }
      statusColor = remainMin <= 30 ? COLOR_URGENT : COLOR_SOON;
    }
    // 开课前不显示 HH:MM 倒计时（避免与状态文本重复）
    countdown = '';
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
    hasCourse: '1',
    name: item.n,
    time: item.t,
    location: item.l,
    teacher: item.c
  };
  return result;
}

/// 构造可下发给卡片页面的完整数据。
export function buildCourseFormData(prefs: preferences.Preferences): Record<string, string> {
  const state = computeCourseState(prefs);
  const data: Record<string, string> = {
    'courseName': state.name,
    'courseTime': state.time,
    'courseLocation': state.location,
    'courseTeacher': state.teacher,
    'courseStatus': state.status,
    'courseStatusColor': state.statusColor,
    'courseStatusTime': state.countdown,
    'progressPercent': state.progress,
    'progressColor': state.progressColor,
    'hasCourse': state.hasCourse
  };
  return data;
}

/// 距离最近课程边界（开课/下课，提前 BOUNDARY_LEAD_MINUTES 分钟）的分钟数。
/// 返回 0 表示没有可调度的未来边界；结果已按系统下限 MIN_NEXT_REFRESH_MINUTES 收敛。
export function minutesToNextBoundary(prefs: preferences.Preferences): number {
  const items = parseCourses(prefs);
  const now = Date.now();
  const leadMs = BOUNDARY_LEAD_MINUTES * 60000;
  let best = 0;
  for (const item of items) {
    const candidates: number[] = [item.s - leadMs, item.e - leadMs];
    for (const c of candidates) {
      if (c <= now) {
        continue;
      }
      const wait = Math.ceil((c - now) / 60000);
      if (best === 0 || wait < best) {
        best = wait;
      }
    }
  }
  if (best === 0 || best > MAX_NEXT_REFRESH_MINUTES) {
    return 0;
  }
  if (best < MIN_NEXT_REFRESH_MINUTES) {
    best = MIN_NEXT_REFRESH_MINUTES;
  }
  return best;
}

/// 预调度"最近的一个课程边界"的系统刷新。
///
/// 说明：`formProvider.setFormNextRefreshTime` 只能登记**一次**待触发的刷新
/// 时间（后调用会覆盖先前的），无法一次性登记多个边界。正确做法是每次只登记
/// 最近的一个边界，待其触发（`onUpdateForm`）后再登记下一个，形成链式预调度，
/// 既能在边界处精确切换，又尽量节省 50 次/天的配额。
export function scheduleNextBoundary(formId: string, prefs: preferences.Preferences): void {
  const minutes = minutesToNextBoundary(prefs);
  if (minutes <= 0) {
    return;
  }
  try {
    formProvider.setFormNextRefreshTime(formId, minutes, (err: BusinessError) => {
      if (err) {
        console.warn(`setFormNextRefreshTime(${minutes}) failed: ${err.code} ${err.message}`);
      }
    });
  } catch (e) {
    console.warn(`setFormNextRefreshTime exception: ${JSON.stringify(e)}`);
  }
}
