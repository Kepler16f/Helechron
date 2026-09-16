import {
  hilog
} from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'CourseWidgetUI';

function formatTime(date: Date): string {
  const h = date.getHours().toString().padStart(2, '0');
  const m = date.getMinutes().toString().padStart(2, '0');
  return `${h}:${m}`;
}

function parseCourseData(raw: string): CourseInfo {
  try {
    const parts = raw.split('|');
    if (parts.length < 4) {
      return { name: '暂无课程', timeRange: '', location: '', teacher: '', minutesLeft: 0, isRunning: false };
    }
    const startDate = new Date(parseInt(parts[2]));
    const endDate = new Date(parseInt(parts[3]));
    const now = new Date();
    const diffMin = Math.round((startDate.getTime() - now.getTime()) / 60000);
    const isRunning = now.getTime() >= startDate.getTime() && now.getTime() < endDate.getTime();
    return {
      name: parts[0] || '未知课程',
      timeRange: `${formatTime(startDate)}-${formatTime(endDate)}`,
      location: parts[4] || '',
      teacher: parts[5] || '',
      minutesLeft: diffMin,
      isRunning: isRunning
    };
  } catch (e) {
    return { name: '暂无课程', timeRange: '', location: '', teacher: '', minutesLeft: 0, isRunning: false };
  }
}

interface CourseInfo {
  name: string;
  timeRange: string;
  location: string;
  teacher: string;
  minutesLeft: number;
  isRunning: boolean;
}

@Entry
@Component
struct CourseWidget {
  @State courseName: string = '暂无课程';
  @State timeRange: string = '';
  @State location: string = '';
  @State teacher: string = '';
  @State statusText: string = '';
  @State statusColor: string = '#999999';

  aboutToAppear(): void {
    try {
      const raw = AppStorage.Get<string>('nextCourse');
      if (raw !== undefined && raw.length > 0) {
        const info = parseCourseData(raw);
        this.courseName = info.name;
        this.timeRange = info.timeRange;
        this.location = info.location;
        this.teacher = info.teacher;
        if (info.isRunning) {
          this.statusText = '上课中';
          this.statusColor = '#4CAF50';
        } else if (info.minutesLeft > 0) {
          if (info.minutesLeft < 60) {
            this.statusText = `${info.minutesLeft}分钟后`;
          } else {
            const h = Math.floor(info.minutesLeft / 60);
            const m = info.minutesLeft % 60;
            this.statusText = m > 0 ? `${h}小时${m}分钟后` : `${h}小时后`;
          }
          this.statusColor = '#FF9800';
        } else {
          this.statusText = '即将开始';
          this.statusColor = '#2196F3';
        }
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `Read course data failed: ${JSON.stringify(e)}`);
    }
  }

  build() {
    Column() {
      Row() {
        Text('\uD83D\uDC68\u200D\uD83C\uDFEB')
          .fontSize(14)
        Text('Helechron')
          .fontSize(11)
          .fontColor('#999999')
          .margin({ left: 4 })
      }
      .width('100%')
      .margin({ bottom: 6 })

      Text(this.courseName)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      if (this.timeRange.length > 0) {
        Row() {
          Text('\u23F0')
            .fontSize(12)
          Text(this.timeRange)
            .fontSize(12)
            .fontColor('#666666')
            .margin({ left: 4 })
        }
        .margin({ top: 4 })
      }

      if (this.location.length > 0) {
        Row() {
          Text('\uD83D\uDCCD')
            .fontSize(12)
          Text(this.location)
            .fontSize(12)
            .fontColor('#666666')
            .margin({ left: 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .margin({ top: 2 })
      }

      if (this.teacher.length > 0) {
        Row() {
          Text('\uD83C\uDF93')
            .fontSize(12)
          Text(this.teacher)
            .fontSize(12)
            .fontColor('#666666')
            .margin({ left: 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .margin({ top: 2 })
      }

      if (this.statusText.length > 0) {
        Text(this.statusText)
          .fontSize(11)
          .fontColor(this.statusColor)
          .fontWeight(FontWeight.Medium)
          .margin({ top: 4 })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .padding(12)
  }
}
