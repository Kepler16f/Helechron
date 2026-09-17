let storageSimpleCourse = new LocalStorage();

@Entry(storageSimpleCourse)
@Component
struct SimpleCourseWidget {
  @LocalStorageProp('courseName') courseName: string = '今日暂无课程';
  @LocalStorageProp('courseTime') courseTime: string = '';
  @LocalStorageProp('courseLocation') courseLocation: string = '';
  @LocalStorageProp('courseTeacher') courseTeacher: string = '';
  @LocalStorageProp('courseStatus') courseStatus: string = '全部结课';
  @LocalStorageProp('courseStatusColor') courseStatusColor: string = '#888888';
  @LocalStorageProp('hasCourse') hasCourse: string = '0';

  build() {
    Column() {
      Row() {
        Text('Helechron')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.widget_text_tertiary'))
      }
      .width('100%')
      .margin({ bottom: 6 })

      Text(this.courseStatus)
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.courseStatusColor)
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 4, bottom: 6 })

      Text(this.courseName)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.widget_text_primary'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ bottom: 6 })

      if (this.hasCourse === '1') {
        Column({ space: 3 }) {
          if (this.courseTime.length > 0) {
            Text(this.courseTime)
              .fontSize(12)
              .fontColor($r('app.color.widget_text_secondary'))
          }
          if (this.courseLocation.length > 0) {
            Text(this.courseLocation)
              .fontSize(12)
              .fontColor($r('app.color.widget_text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          if (this.courseTeacher.length > 0) {
            Text(this.courseTeacher)
              .fontSize(11)
              .fontColor($r('app.color.widget_text_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')
      }
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
