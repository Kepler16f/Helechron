let storageSimpleCourse = new LocalStorage();

@Entry(storageSimpleCourse)
@Component
struct SimpleCourseWidget {
  @LocalStorageProp('courseName') courseName: string = '今日暂无课程';
  @LocalStorageProp('courseTime') courseTime: string = '';
  @LocalStorageProp('courseLocation') courseLocation: string = '';
  @LocalStorageProp('courseStatus') courseStatus: string = '全部结课';
  @LocalStorageProp('courseStatusColor') courseStatusColor: string = '#888888';
  @LocalStorageProp('courseDate') courseDate: string = '';
  @LocalStorageProp('hasCourse') hasCourse: string = '0';

  build() {
    Column() {
      Row() {
        Text('Helechron')
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.widget_text_tertiary'))
      }
      .width('100%')

      Text(this.courseStatus)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.courseStatusColor)
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 8 })

      Text(this.courseName)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.widget_text_primary'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 })

      if (this.hasCourse === '1') {
        if (this.courseDate.length > 0) {
          Row({ space: 4 }) {
            Text(this.courseDate)
              .fontSize(11)
              .fontColor($r('app.color.widget_text_secondary'))
            if (this.courseTime.length > 0) {
              Text(this.courseTime)
                .fontSize(11)
                .fontColor($r('app.color.widget_text_secondary'))
            }
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ top: 6 })
        }

        if (this.courseLocation.length > 0) {
          Text(this.courseLocation)
            .fontSize(11)
            .fontColor($r('app.color.widget_text_tertiary'))
            .textAlign(TextAlign.Center)
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
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
