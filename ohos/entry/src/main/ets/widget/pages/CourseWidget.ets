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
  @LocalStorageProp('hasCourse') hasCourse: string = '0';

  build() {
    Column() {
      // 头部栏：品牌 + 状态标签
      Row() {
        Text('Helechron')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor('#888888')

        Blank()

        if (this.courseStatus.length > 0) {
          Text(this.courseStatus)
            .fontSize(11)
            .fontColor(this.courseStatusColor)
            .fontWeight(FontWeight.Medium)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('#12000000')
            .borderRadius(4)
        }
      }
      .width('100%')
      .margin({ bottom: 6 })

      // 课程名
      Text(this.courseName)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Blank()

      // 底部课程元数据：时间、地点、教师
      Column({ space: 3 }) {
        if (this.courseTime.length > 0) {
          Row() {
            Text(this.courseTime)
              .fontSize(12)
              .fontColor('#444444')
          }
          .width('100%')
        }

        if (this.courseLocation.length > 0) {
          Row() {
            Text(this.courseLocation)
              .fontSize(12)
              .fontColor('#666666')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
        }

        if (this.courseTeacher.length > 0) {
          Row() {
            Text(this.courseTeacher)
              .fontSize(11)
              .fontColor('#888888')
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
    .backgroundColor('#FFFFFF')
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
