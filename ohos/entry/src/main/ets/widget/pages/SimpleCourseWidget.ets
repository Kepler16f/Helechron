let storageSimpleCourse = new LocalStorage();

@Entry(storageSimpleCourse)
@Component
struct SimpleCourseWidget {
  @LocalStorageProp('courseName') courseName: string = '今日暂无课程';
  @LocalStorageProp('courseTime') courseTime: string = '';
  @LocalStorageProp('courseLocation') courseLocation: string = '';
  @LocalStorageProp('courseTeacher') courseTeacher: string = '';
  @LocalStorageProp('courseStatus') courseStatus: string = '全部结课';
  @LocalStorageProp('courseStatusColor') courseStatusColor: string = '#6B7280';
  @LocalStorageProp('accentColor') accentColor: string = '#007AFF';
  @LocalStorageProp('courseDate') courseDate: string = '';
  @LocalStorageProp('hasCourse') hasCourse: string = '0';

  build() {
    Column() {
      // 顶部品牌标识 + 日期胶囊（严格单行）
      Row({ space: 5 }) {
        Circle({ width: 6, height: 6 })
          .fill(this.hasCourse === '1' ? this.courseStatusColor : this.accentColor)
        Text('Helechron')
          .fontSize(10.5)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.widget_text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        if (this.hasCourse === '1' && this.courseDate.length > 0) {
          Text(this.courseDate)
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.widget_text_secondary'))
            .maxLines(1)
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .borderRadius(99)
            .backgroundColor($r('app.color.widget_tonal_surface'))
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 核心状态标题：严格单行 + 自适应字号，绝不换行断字
      Text(this.courseStatus)
        .fontSize(16)
        .maxFontSize(16)
        .minFontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.courseStatusColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 7 })

      // 课程名称：严格单行显示
      Text(this.courseName)
        .fontSize(14)
        .maxFontSize(14)
        .minFontSize(11.5)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.widget_text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 3 })

      Blank()

      // 底部 Tonal 信息子块（对齐 0.2.0 Ael 三层卡片层次）
      if (this.hasCourse === '1') {
        Column({ space: 3 }) {
          if (this.courseTime.length > 0) {
            Row({ space: 5 }) {
              Column()
                .width(3)
                .height(11)
                .borderRadius(1.5)
                .backgroundColor(this.courseStatusColor)
              Text(this.courseTime)
                .fontSize(11.5)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.widget_text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }

          if (this.courseLocation.length > 0 || this.courseTeacher.length > 0) {
            Row({ space: 4 }) {
              Text(this.courseLocation.length > 0 ? this.courseLocation : this.courseTeacher)
                .fontSize(10.5)
                .fontColor($r('app.color.widget_text_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)

              if (this.courseLocation.length > 0 && this.courseTeacher.length > 0) {
                Text(this.courseTeacher)
                  .fontSize(10.5)
                  .fontColor($r('app.color.widget_text_tertiary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: '42%' })
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .borderRadius(11)
        .backgroundColor($r('app.color.widget_tonal_surface'))
      } else {
        Row() {
          Text('享受轻松的课余时光')
            .fontSize(10.5)
            .fontColor($r('app.color.widget_text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .borderRadius(11)
        .backgroundColor($r('app.color.widget_tonal_surface'))
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor($r('app.color.widget_background'))
    .borderRadius(20)
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
