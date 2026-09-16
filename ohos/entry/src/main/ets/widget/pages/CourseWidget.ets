@Entry
@Component
struct CourseWidget {
  @LocalStorageProp('courseData') courseData: string = '';
  courseName: string = '暂无课程';
  courseTime: string = '';
  courseLocation: string = '';
  courseTeacher: string = '';
  courseStatus: string = '';
  courseStatusColor: string = '#999999';

  aboutToAppear(): void {
    this.parseCourse();
  }

  parseCourse(): void {
    if (this.courseData.length === 0) {
      return;
    }
    try {
      const parts = this.courseData.split('|');
      if (parts.length < 4) {
        return;
      }
      this.courseName = parts[0] || '未知课程';
      const startMs = parseInt(parts[2]);
      const endMs = parseInt(parts[3]);
      if (isNaN(startMs) || isNaN(endMs)) {
        return;
      }
      const start = new Date(startMs);
      const end = new Date(endMs);
      const pad = (n: number): string => n.toString().padStart(2, '0');
      this.courseTime = `${pad(start.getHours())}:${pad(start.getMinutes())}-${pad(end.getHours())}:${pad(end.getMinutes())}`;
      this.courseLocation = parts[4] || '';
      this.courseTeacher = parts[5] || '';
      const now = new Date();
      const diffMin = Math.round((start.getTime() - now.getTime()) / 60000);
      const running = now.getTime() >= start.getTime() && now.getTime() < end.getTime();
      if (running) {
        this.courseStatus = '上课中';
        this.courseStatusColor = '#4CAF50';
      } else if (diffMin > 0) {
        if (diffMin < 60) {
          this.courseStatus = `${diffMin}分钟后`;
        } else {
          const h = Math.floor(diffMin / 60);
          const m = diffMin % 60;
          this.courseStatus = m > 0 ? `${h}小时${m}分钟后` : `${h}小时后`;
        }
        this.courseStatusColor = '#FF9800';
      } else {
        this.courseStatus = '即将开始';
        this.courseStatusColor = '#2196F3';
      }
    } catch (e) {
      // keep defaults
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
