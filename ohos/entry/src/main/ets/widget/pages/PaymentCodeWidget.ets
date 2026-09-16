import preferences from '@ohos.data.preferences';

const PREFS_NAME = 'helechron_widget_data';

@Entry
@Component
struct PaymentCodeWidget {
  paymentCode: string = '10000000000000000001';
  displayName: string = '付款码';
  qrReady: boolean = false;

  aboutToAppear(): void {
    this.loadFromPrefs();
  }

  async loadFromPrefs(): Promise<void> {
    try {
      const ctx = getContext(this);
      const prefs = await preferences.getPreferences(ctx, PREFS_NAME);
      const code = await prefs.get('paymentCode', '') as string;
      const name = await prefs.get('displayName', '') as string;
      if (code !== null && code !== undefined && code.length > 0) {
        this.paymentCode = code;
      }
      if (name !== null && name !== undefined && name.length > 0) {
        this.displayName = name;
      }
    } catch (e) {
      // use defaults
    }
    this.qrReady = true;
  }

  drawQrCode(ctx: CanvasRenderingContext2D, code: string, size: number): void {
    const cellSize = size / 21;
    const grid = this.generateGrid(code);

    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(0, 0, size, size);

    ctx.fillStyle = '#000000';
    for (let row = 0; row < 21; row++) {
      for (let col = 0; col < 21; col++) {
        if (grid[row][col]) {
          ctx.fillRect(col * cellSize, row * cellSize, cellSize, cellSize);
        }
      }
    }

    this.drawFinderPattern(ctx, 0, 0, cellSize);
    this.drawFinderPattern(ctx, 14 * cellSize, 0, cellSize);
    this.drawFinderPattern(ctx, 0, 14 * cellSize, cellSize);
  }

  drawFinderPattern(ctx: CanvasRenderingContext2D, x: number, y: number, cs: number): void {
    ctx.fillStyle = '#000000';
    ctx.fillRect(x, y, 7 * cs, 7 * cs);
    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(x + cs, y + cs, 5 * cs, 5 * cs);
    ctx.fillStyle = '#000000';
    ctx.fillRect(x + 2 * cs, y + 2 * cs, 3 * cs, 3 * cs);
  }

  generateGrid(code: string): boolean[][] {
    const grid: boolean[][] = [];
    let seed = this.simpleHash(code);
    for (let i = 0; i < 21; i++) {
      grid[i] = [];
      for (let j = 0; j < 21; j++) {
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
        grid[i][j] = (seed % 3) !== 0;
      }
    }
    for (let i = 0; i < 8; i++) {
      for (let j = 8; j < 13; j++) {
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
        grid[i][j] = (seed % 2) === 0;
      }
    }
    for (let i = 8; i < 13; i++) {
      for (let j = 0; j < 3; j++) {
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
        grid[i][j] = (seed % 2) === 0;
      }
    }
    return grid;
  }

  simpleHash(str: string): number {
    let hash = 5381;
    for (let i = 0; i < str.length; i++) {
      hash = ((hash << 5) + hash + str.charCodeAt(i)) & 0xFFFFFFFF;
    }
    return hash;
  }

  build() {
    Column() {
      Text(this.displayName)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .margin({ bottom: 8 })

      if (this.qrReady) {
        Canvas()
          .width('100%')
          .aspectRatio(1)
      } else {
        Text('加载中...')
          .fontSize(12)
          .fontColor('#CCCCCC')
      }

      Text(this.paymentCode)
        .fontSize(10)
        .fontColor('#999999')
        .margin({ top: 6 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(12)
  }
}
