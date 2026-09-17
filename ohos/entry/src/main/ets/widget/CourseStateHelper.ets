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
/// 课程进行中 / 进入倒计时窗口时的刷新间隔（分钟）
const ACTIVE_REFRESH_MINUTES = 20;
/// 距下一节课还很远时的兜底刷新间隔（分钟）
const IDLE_REFRESH_MINUTES = 180;
/// 每个课程边界调度的提前量（分钟），确保不晚于边界触发
const BOUNDARY_LEAD_MINUTES = 1;

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

  let status = '';
  let statusColor = COLOR_SOON;
  let progress = 0;
  let countdown = '';

  if (now >= item.s && now < item.e) {
    const total = item.e - item.s;
    const elapsed = now - item.s;
    progress = total <= 0 ? 100 : (elapsed / total) * 100;
    status = '上课中';
    statusColor = COLOR_ONGOING;
    const remainMin = Math.floor((item.e - now) / 60000);
    countdown = `${pad2(Math.floor(remainMin / 60))}:${pad2(remainMin % 60)}`;
  } else {
    const remainMin = Math.floor((item.s - now) / 60000);
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

/// 计算下一次系统刷新应等待的分钟数（受 50 次/天配额约束的策略）：
/// - 课程进行中或已进入倒计时窗口：到下一个精确边界的时间；
/// - 距开课尚远：睡到"进入倒计时窗口"的时刻（上限 IDLE_REFRESH_MINUTES）；
/// - 无后续课程：IDLE_REFRESH_MINUTES 兜底。
export function nextRefreshMinutes(prefs: preferences.Preferences): number {
  const items = parseCourses(prefs);
  const leadMin = getNum(prefs, 'leadWindowMinutes', DEFAULT_LEAD_MINUTES);
  const now = Date.now();
  const item = pickCurrentOrNext(items, now);
  if (item === null) {
    return IDLE_REFRESH_MINUTES;
  }

  const ongoing = now >= item.s && now < item.e;
  const withinLead = now < item.s && item.s - now <= leadMin * 60000;

  let wait: number;
  if (ongoing) {
    // 课程进行中 → 精确到下课时间
    wait = Math.ceil((item.e - now) / 60000);
  } else if (withinLead) {
    // 已进入倒计时窗口 → 精确到开课时间
    wait = Math.ceil((item.s - now) / 60000);
  } else {
    // 距开课尚远 → 睡到倒计时窗口开始
    wait = Math.ceil((item.s - leadMin * 60000 - now) / 60000);
    if (wait <= 0) {
      wait = MIN_NEXT_REFRESH_MINUTES;
    }
    // 但不超过 IDLE_REFRESH_MINUTES（updateDuration 30分钟会兜底）
    if (wait > IDLE_REFRESH_MINUTES) {
      wait = IDLE_REFRESH_MINUTES;
    }
  }

  if (wait < MIN_NEXT_REFRESH_MINUTES) {
    wait = MIN_NEXT_REFRESH_MINUTES;
  }
  return wait;
}

/// 调度单次系统刷新（基于 nextRefreshMinutes 计算）。
export function scheduleBoundaryRefresh(formId: string, prefs: preferences.Preferences): void {
  const minutes = nextRefreshMinutes(prefs);
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

/// 预调度所有未来课程边界（开课/下课）的系统刷新。
/// 每个边界提前 BOUNDARY_LEAD_MINUTES 分钟调度，确保状态切换时立即刷新。
/// 配额消耗：N 节课 → 最多 2N 次（每节开课+下课各一次）。
export function scheduleAllBoundaries(formId: string, prefs: preferences.Preferences): void {
  const items = parseCourses(prefs);
  const now = Date.now();
  let scheduled = 0;

  for (const item of items) {
    // 调度开课边界（start - BOUNDARY_LEAD_MINUTES）
    const startWait = Math.ceil((item.s - BOUNDARY_LEAD_MINUTES * 60000 - now) / 60000);
    if (startWait >= MIN_NEXT_REFRESH_MINUTES && startWait <= 60 * 24) {
      trySetFormNextRefreshTime(formId, startWait);
      scheduled++;
    }

    // 调度下课边界（end - BOUNDARY_LEAD_MINUTES）
    const endWait = Math.ceil((item.e - BOUNDARY_LEAD_MINUTES * 60000 - now) / 60000);
    if (endWait >= MIN_NEXT_REFRESH_MINUTES && endWait <= 60 * 24) {
      trySetFormNextRefreshTime(formId, endWait);
      scheduled++;
    }
  }

  if (scheduled > 0) {
    console.info(`CourseWidget: scheduled ${scheduled} boundary refreshes for ${formId}`);
  }
}

function trySetFormNextRefreshTime(formId: string, minutes: number): void {
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
