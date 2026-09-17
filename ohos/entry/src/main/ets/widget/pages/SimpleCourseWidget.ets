let storageSimpleCourse = new LocalStorage();

@Entry(storageSimpleCourse)
@Component
struct SimpleCourseWidget {
  @LocalStorageProp('courseName') courseName: string = '今日暂无课程';
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
      .margin({ bottom: 4 })

      Text(this.courseStatus)
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.courseStatusColor)
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 2, bottom: 4 })

      Text(this.courseName)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.widget_text_primary'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.hasCourse === '1' && this.courseDate.length > 0) {
        Text(this.courseDate)
          .fontSize(12)
          .fontColor($r('app.color.widget_text_secondary'))
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ top: 4 })
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor($r('app.color.widget_background'))
    .borderRadius(16)
    .justifyContent(FlexAlign.Center)
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
