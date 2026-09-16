import preferences from '@ohos.data.preferences';

const PREFS_NAME = 'helechron_widget_data';

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
  courseName: string = '暂无课程';
  courseTime: string = '';
  courseLocation: string = '';
  courseTeacher: string = '';
  courseStatus: string = '';
  courseStatusColor: string = '#999999';

  aboutToAppear(): void {
    this.loadFromPrefs();
  }

  async loadFromPrefs(): Promise<void> {
    try {
      const ctx = getContext(this);
      const prefs = await preferences.getPreferences(ctx, PREFS_NAME);
      const raw = await prefs.get('nextCourse', '') as string;
      if (raw !== null && raw !== undefined && raw.length > 0) {
        const info = parseCourseData(raw);
        this.courseName = info.name;
        this.courseTime = info.timeRange;
        this.courseLocation = info.location;
        this.courseTeacher = info.teacher;
        if (info.isRunning) {
          this.courseStatus = '上课中';
          this.courseStatusColor = '#4CAF50';
        } else if (info.minutesLeft > 0) {
          if (info.minutesLeft < 60) {
            this.courseStatus = `${info.minutesLeft}分钟后`;
          } else {
            const h = Math.floor(info.minutesLeft / 60);
            const m = info.minutesLeft % 60;
            this.courseStatus = m > 0 ? `${h}小时${m}分钟后` : `${h}小时后`;
          }
          this.courseStatusColor = '#FF9800';
        } else {
          this.courseStatus = '即将开始';
          this.courseStatusColor = '#2196F3';
        }
      }
    } catch (e) {
      // use defaults
    }
  }

  build() {
    Column() {
      Row() {
        Text('Helechron')
          .fontSize(11)
          .fontColor('#999999')
      }
      .width('100%')
      .margin({ bottom: 6 })

      Text(this.courseName)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      if (this.courseTime.length > 0) {
        Text(this.courseTime)
          .fontSize(12)
          .fontColor('#666666')
          .margin({ top: 4 })
      }

      if (this.courseLocation.length > 0) {
        Text(this.courseLocation)
          .fontSize(12)
          .fontColor('#666666')
          .margin({ top: 2 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (this.courseTeacher.length > 0) {
        Text(this.courseTeacher)
          .fontSize(12)
          .fontColor('#666666')
          .margin({ top: 2 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (this.courseStatus.length > 0) {
        Text(this.courseStatus)
          .fontSize(11)
          .fontColor(this.courseStatusColor)
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
