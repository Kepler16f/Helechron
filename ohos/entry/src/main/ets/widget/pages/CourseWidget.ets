let storageCourse = new LocalStorage();

@Entry(storageCourse)
@Component
struct CourseWidget {
  @LocalStorageProp('courseName') courseName: string = '今日暂无课程';
  @LocalStorageProp('courseTime') courseTime: string = '';
  @LocalStorageProp('courseLocation') courseLocation: string = '';
  @LocalStorageProp('courseTeacher') courseTeacher: string = '';
  @LocalStorageProp('courseStatus') courseStatus: string = '全部结课';
  @LocalStorageProp('courseStatusColor') courseStatusColor: string = '#6B7280';
  @LocalStorageProp('statusBadgeBg') statusBadgeBg: string = '#1A6B7280';
  @LocalStorageProp('accentColor') accentColor: string = '#007AFF';
  @LocalStorageProp('courseStatusTime') courseStatusTime: string = '';
  @LocalStorageProp('progressPercent') progressPercent: string = '0';
  @LocalStorageProp('progressColor') progressColor: string = '#007AFF';
  @LocalStorageProp('showProgress') showProgress: string = '0';
  @LocalStorageProp('hasCourse') hasCourse: string = '0';

  build() {
    Column() {
      // 顶部：品牌圆点 + 状态胶囊（严格单行）+ 刷新按钮
      Row({ space: 6 }) {
        Circle({ width: 6, height: 6 })
          .fill(this.accentColor)
        Text('Helechron')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.widget_text_tertiary'))
          .maxLines(1)

        Row({ space: 4 }) {
          Circle({ width: 5, height: 5 })
            .fill(this.courseStatusColor)
          Text(this.courseStatusTime.length > 0
            ? `${this.courseStatus} · ${this.courseStatusTime}`
            : this.courseStatus)
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.courseStatusColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .borderRadius(99)
        .backgroundColor(this.statusBadgeBg)
        .alignItems(VerticalAlign.Center)
        .constraintSize({ maxWidth: '56%' })

        Blank()

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Image($r('app.media.ic_widget_refresh'))
            .width(13)
            .height(13)
            .fillColor($r('app.color.widget_button_text'))
        }
        .width(26)
        .height(26)
        .backgroundColor(this.accentColor)
        .onClick(() => {
          postCardAction(this, {
            action: 'message',
            params: {
              event: 'refresh_course'
            }
          });
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 课程标题：严格单行自适应显示
      Text(this.courseName)
        .fontSize(17)
        .maxFontSize(17)
        .minFontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.widget_text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 7 })

      // 进度条（上课中或即将上课时展示）
      if (this.hasCourse === '1' && this.showProgress === '1') {
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
        .margin({ top: 7 })
      }

      Blank()

      // 底部 Tonal 信息子容器（单行紧凑排版）
      if (this.hasCourse === '1') {
        Row({ space: 7 }) {
          Column()
            .width(3)
            .height(12)
            .borderRadius(1.5)
            .backgroundColor(this.courseStatusColor)

          if (this.courseTime.length > 0) {
            Text(this.courseTime)
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.widget_text_primary'))
              .maxLines(1)
          }

          if (this.courseLocation.length > 0) {
            Text(this.courseLocation)
              .fontSize(12)
              .fontColor($r('app.color.widget_text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          } else {
            Blank()
          }

          if (this.courseTeacher.length > 0) {
            Text(this.courseTeacher)
              .fontSize(11.5)
              .fontColor($r('app.color.widget_text_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: '28%' })
          }
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 7, bottom: 7 })
        .borderRadius(12)
        .backgroundColor($r('app.color.widget_tonal_surface'))
        .alignItems(VerticalAlign.Center)
      } else {
        Row({ space: 6 }) {
          Circle({ width: 5, height: 5 })
            .fill($r('app.color.widget_text_tertiary'))
          Text('今日课程已全部结束，好好休息')
            .fontSize(11.5)
            .fontColor($r('app.color.widget_text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 7, bottom: 7 })
        .borderRadius(12)
        .backgroundColor($r('app.color.widget_tonal_surface'))
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .padding(14)
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
