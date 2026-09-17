import preferences from '@ohos.data.preferences';
import { BusinessError } from '@kit.BasicServicesKit';
import { formProvider } from '@kit.FormKit';

const COLOR_ONGOING = '#4CAF50';
const COLOR_SOON = '#2196F3';
const COLOR_IDLE = '#888888';
const COLOR_ENDED = '#9E9E9E';

const MIN_NEXT_REFRESH_MINUTES = 5;
const SIMPLE_BOUNDARY_LEAD_MINUTES = 10;

interface SimpleCourseItem {
  s: number;
  e: number;
  n: string;
  t: string;
  l: string;
  c: string;
}

function getStr(prefs: preferences.Preferences, key: string, def: string): string {
  const v = prefs.getSync(key, def);
  return typeof v === 'string' ? v : def;
}

function parseCourses(prefs: preferences.Preferences): SimpleCourseItem[] {
  const json = getStr(prefs, 'coursesJson', '');
  const items: SimpleCourseItem[] = [];
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
      const item: SimpleCourseItem = {
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
    console.error(`SimpleCourseStateHelper parseCourses failed: ${JSON.stringify(err)}`);
  }
  return items;
}

function pickCurrentOrNext(items: SimpleCourseItem[], now: number): SimpleCourseItem | null {
  let best: SimpleCourseItem | null = null;
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

function idleState(): Record<string, string> {
  return {
    'courseName': '今日暂无课程',
    'courseStatus': '全部结课',
    'courseStatusColor': COLOR_IDLE,
    'hasCourse': '0'
  };
}

export function buildSimpleCourseFormData(prefs: preferences.Preferences): Record<string, string> {
  const items = parseCourses(prefs);
  const now = Date.now();
  const item = pickCurrentOrNext(items, now);
  if (item === null) {
    return idleState();
  }

  let status = '';
  let statusColor = COLOR_SOON;

  if (now >= item.s && now < item.e) {
    status = '上课中';
    statusColor = COLOR_ONGOING;
  } else {
    const diffMin = Math.floor((item.s - now) / 60000);
    if (diffMin <= 0) {
      status = '即将开始';
      statusColor = COLOR_SOON;
    } else if (diffMin <= 10) {
      status = `${diffMin}分钟后上课`;
      statusColor = COLOR_SOON;
    } else {
      status = '待上课';
      statusColor = COLOR_ENDED;
    }
  }

  return {
    'courseName': item.n,
    'courseTime': item.t,
    'courseLocation': item.l,
    'courseTeacher': item.c,
    'courseStatus': status,
    'courseStatusColor': statusColor,
    'hasCourse': '1'
  };
}

/// 计算距离下一个简单课程边界（课前10分钟 / 上课 / 下课）的分钟数。
export function minutesToNextSimpleBoundary(prefs: preferences.Preferences): number {
  const items = parseCourses(prefs);
  const now = Date.now();
  const leadMs = SIMPLE_BOUNDARY_LEAD_MINUTES * 60000;
  let best = 0;
  for (const item of items) {
    const candidates: number[] = [item.s - leadMs, item.s, item.e];
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
  if (best === 0 || best > 60 * 24) {
    return 0;
  }
  if (best < MIN_NEXT_REFRESH_MINUTES) {
    best = MIN_NEXT_REFRESH_MINUTES;
  }
  return best;
}

export function scheduleSimpleBoundary(formId: string, prefs: preferences.Preferences): void {
  const minutes = minutesToNextSimpleBoundary(prefs);
  if (minutes <= 0) {
    return;
  }
  try {
    formProvider.setFormNextRefreshTime(formId, minutes, (err: BusinessError) => {
      if (err) {
        console.warn(`scheduleSimpleBoundary(${minutes}) failed: ${err.code} ${err.message}`);
      }
    });
  } catch (e) {
    console.warn(`scheduleSimpleBoundary exception: ${JSON.stringify(e)}`);
  }
}
