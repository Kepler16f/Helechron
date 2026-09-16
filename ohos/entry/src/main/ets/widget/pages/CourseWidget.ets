let storageCourse = new LocalStorage();

@Entry(storageCourse)
@Component
struct CourseWidget {
  @LocalStorageProp('courseName') courseName: string = '今日暂无课程';
  @LocalStorageProp('courseTime') courseTime: string = '';
  @LocalStorageProp('courseLocation') courseLocation: string = '';
  @LocalStorageProp('courseTeacher') courseTeacher: string = '';
  @LocalStorageProp('courseStatus') courseStatus: string = '全部结课';
  @LocalStorageProp('courseStatusColor') courseStatusColor: string = '#888888';
  @LocalStorageProp('progressPercent') progressPercent: string = '0';
  @LocalStorageProp('progressColor') progressColor: string = '#1E88E5';
  @LocalStorageProp('hasCourse') hasCourse: string = '0';

  build() {
    Column() {
      // 头部栏：品牌 + 状态标签
      Row() {
        Text('Helechron')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.widget_text_tertiary'))

        Blank()

        Text(this.courseStatus)
          .fontSize(11)
          .fontColor(this.courseStatusColor)
          .fontWeight(FontWeight.Medium)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor($r('app.color.widget_badge_background'))
          .borderRadius(4)
      }
      .width('100%')
      .margin({ bottom: 8 })

      // 课程名
      Text(this.courseName)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.widget_text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      // 倒计时进度条
      if (this.hasCourse === '1') {
        Stack({ alignContent: Alignment.Start }) {
          Row() {
          }
          .width('100%')
          .height(6)
          .backgroundColor($r('app.color.widget_progress_track'))
          .borderRadius(3)

          Row() {
          }
          .width(this.progressPercent + '%')
          .height(6)
          .backgroundColor(this.progressColor)
          .borderRadius(3)
        }
        .width('100%')
        .margin({ top: 8, bottom: 8 })
      } else {
        Blank()
      }

      // 底部课程元数据：时间、地点、教师
      Column({ space: 3 }) {
        if (this.courseTime.length > 0) {
          Row() {
            Text(this.courseTime)
              .fontSize(12)
              .fontColor($r('app.color.widget_text_secondary'))
          }
          .width('100%')
        }

        if (this.courseLocation.length > 0) {
          Row() {
            Text(this.courseLocation)
              .fontSize(12)
              .fontColor($r('app.color.widget_text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
        }

        if (this.courseTeacher.length > 0) {
          Row() {
            Text(this.courseTeacher)
              .fontSize(11)
              .fontColor($r('app.color.widget_text_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
        }
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(14)
    .backgroundColor($r('app.color.widget_background'))
    .borderRadius(16)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: {
          target: 'scholar'
        }
      });
    })
  }
}
