@Entry
@Component
struct CourseWidget {
  courseName: string = '暂无课程';
  courseTime: string = '';
  courseLocation: string = '';
  courseTeacher: string = '';
  courseStatus: string = '';
  courseStatusColor: string = '#999999';

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
