const QR_SIZE = 21;

@Entry
@Component
struct PaymentCodeWidget {
  paymentCode: string = '10000000000000000001';
  displayName: string = '付款码';

  drawQrCode(ctx: CanvasRenderingContext2D, code: string, size: number): void {
    const cellSize = size / QR_SIZE;
    const grid = this.generateGrid(code);

    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(0, 0, size, size);

    ctx.fillStyle = '#000000';
    for (let row = 0; row < QR_SIZE; row++) {
      for (let col = 0; col < QR_SIZE; col++) {
        if (grid[row][col]) {
          ctx.fillRect(col * cellSize, row * cellSize, cellSize, cellSize);
        }
      }
    }

    this.drawFinderPattern(ctx, 0, 0, cellSize);
    this.drawFinderPattern(ctx, (QR_SIZE - 7) * cellSize, 0, cellSize);
    this.drawFinderPattern(ctx, 0, (QR_SIZE - 7) * cellSize, cellSize);
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
    for (let i = 0; i < QR_SIZE; i++) {
      grid[i] = [];
      for (let j = 0; j < QR_SIZE; j++) {
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
        grid[i][j] = (seed % 3) !== 0;
      }
    }
    for (let i = 0; i < 8; i++) {
      for (let j = 8; j < QR_SIZE - 8; j++) {
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
        grid[i][j] = (seed % 2) === 0;
      }
    }
    for (let i = 8; i < QR_SIZE - 8; i++) {
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
