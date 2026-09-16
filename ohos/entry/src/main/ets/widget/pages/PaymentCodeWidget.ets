let storagePaymentCode = new LocalStorage();

@Entry(storagePaymentCode)
@Component
struct PaymentCodeWidget {
  @LocalStorageProp('paymentCode') paymentCode: string = '10000000000000000001';
  @LocalStorageProp('displayName') displayName: string = '付款码';

  drawQrCode(ctx: CanvasRenderingContext2D, code: string, size: number): void {
    const cs = size / 21;
    const grid = this.generateGrid(code);
    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(0, 0, size, size);
    ctx.fillStyle = '#000000';
    for (let r = 0; r < 21; r++) {
      for (let c = 0; c < 21; c++) {
        if (grid[r][c]) {
          ctx.fillRect(c * cs, r * cs, cs, cs);
        }
      }
    }
    this.fillFinder(ctx, 0, 0, cs);
    this.fillFinder(ctx, 14 * cs, 0, cs);
    this.fillFinder(ctx, 0, 14 * cs, cs);
  }

  fillFinder(ctx: CanvasRenderingContext2D, x: number, y: number, cs: number): void {
    ctx.fillStyle = '#000000';
    ctx.fillRect(x, y, 7 * cs, 7 * cs);
    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(x + cs, y + cs, 5 * cs, 5 * cs);
    ctx.fillStyle = '#000000';
    ctx.fillRect(x + 2 * cs, y + 2 * cs, 3 * cs, 3 * cs);
  }

  generateGrid(code: string): boolean[][] {
    const grid: boolean[][] = [];
    let seed = this.h(code);
    for (let i = 0; i < 21; i++) {
      grid[i] = [];
      for (let j = 0; j < 21; j++) {
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
        grid[i][j] = (seed % 3) !== 0;
      }
    }
    return grid;
  }

  h(s: string): number {
    let v = 5381;
    for (let i = 0; i < s.length; i++) {
      v = ((v << 5) + v + s.charCodeAt(i)) & 0xFFFFFFFF;
    }
    return v;
  }

  build() {
    Column() {
      Text(this.displayName)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .margin({ bottom: 8 })
      Canvas()
        .width('100%')
        .aspectRatio(1)
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
