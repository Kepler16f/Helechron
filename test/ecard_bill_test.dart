import 'dart:io';

import 'package:celechron/http/zjuServices/ecard.dart';
import 'package:celechron/http/zjuServices/exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ECardTransaction.fromJson', () {
    test('parses standard Berserker record with cent amounts and local date string', () {
      final tx = ECardTransaction.fromJson({
        'orderId': 'ORD001',
        'tranamt': 1560,
        'typeFrom': '2',
        'turnoverType': '二维码支付',
        'toMerchant': '紫金港玉湖餐厅',
        'resume': '紫金港玉湖餐厅-扫码支付',
        'effectdateStr': '2026-11-10 12:15:30',
        'cardBalance': 8440,
      });

      expect(tx.orderId, 'ORD001');
      expect(tx.amount, closeTo(15.60, 0.001));
      expect(tx.isIncome, isFalse);
      expect(tx.merchant, '紫金港玉湖餐厅');
      expect(tx.balanceAfter, closeTo(84.40, 0.001));
      expect(tx.dateTime, DateTime(2026, 11, 10, 12, 15, 30));
    });

    test('supports alternate amount, comma string, ebagamt balance and ISO UTC date', () {
      final tx = ECardTransaction.fromJson({
        'orderId': 'ORD002',
        'transAmt': '20,000',
        'typeFrom': '1',
        'turnoverType': '微信充值',
        'merchantName': '校园卡电子账户',
        'effectdate': '2026-11-05T04:30:00.000Z',
        'ebagamt': 25000,
      });

      final expectedLocal = DateTime.utc(2026, 11, 5, 4, 30).toLocal();
      expect(tx.amount, closeTo(200.0, 0.001));
      expect(tx.isIncome, isTrue);
      expect(tx.balanceAfter, closeTo(250.0, 0.001));
      expect(tx.dateTime, expectedLocal);
    });
  });

  group('ECard.parseTransactionPage', () {
    test('accepts data.rows and direct list under data', () {
      final pageRows = ECard.parseTransactionPage({
        'code': 200,
        'data': {
          'rows': [
            {
              'orderId': 'A1',
              'tranamt': 500,
              'typeFrom': '2',
              'toMerchant': '教育超市',
              'effectdateStr': '2026-11-01 09:00:00',
            }
          ],
          'total': 1,
          'pages': 1,
        },
      });
      expect(pageRows.records.length, 1);
      expect(pageRows.records.first.amount, closeTo(5.0, 0.001));

      final pageDirectList = ECard.parseTransactionPage({
        'code': 200,
        'data': [
          {
            'orderId': 'A2',
            'tranamt': 800,
            'typeFrom': '2',
            'toMerchant': '麦香餐厅',
            'effectdateStr': '2026-11-02 18:00:00',
          }
        ],
      });
      expect(pageDirectList.records.length, 1);
      expect(pageDirectList.records.first.merchant, '麦香餐厅');
    });

    test('throws AuthenticationExpiredException on auth errors', () {
      expect(
        () => ECard.parseTransactionPage({'code': 401, 'message': '未登录'}),
        throwsA(isA<AuthenticationExpiredException>()),
      );
    });
  });

  group('ECard.fetchMonthTransactions resilience', () {
    test('falls back to unfiltered pagination and slices target month when timeFrom/timeTo zeros out', () async {
      final calls = <Map<String, Object?>>[];
      final client = HttpClient();
      try {
        final result = await ECard.fetchMonthTransactions(
          client,
          'dummy-token',
          month: DateTime(2026, 10, 1),
          eCardAccount: 'CARD123',
          now: DateTime(2026, 11, 12),
          pageLoader: ({
            required int page,
            required int size,
            String? timeFrom,
            String? timeTo,
            String? eCardAccount,
            required bool filterByAccount,
            required String synAccessSource,
          }) async {
            calls.add({
              'page': page,
              'timeFrom': timeFrom,
              'timeTo': timeTo,
              'filterByAccount': filterByAccount,
              'source': synAccessSource,
            });
            // 模拟带 timeFrom 时后端返回空，且仅 synAccessSource == 'app' 有完整数据
            if (timeFrom != null || timeTo != null) {
              return const ECardTransactionPage(
                  records: [], total: 0, pages: 0, currentPage: 1);
            }
            if (synAccessSource != 'app') {
              return const ECardTransactionPage(
                  records: [], total: 0, pages: 0, currentPage: 1);
            }
            if (page == 1) {
              return ECardTransactionPage(
                records: [
                  ECardTransaction.fromJson({
                    'orderId': 'NOV1',
                    'tranamt': 1200,
                    'typeFrom': '2',
                    'toMerchant': '十一月消费',
                    'effectdateStr': '2026-11-08 11:30:00',
                  }),
                  ECardTransaction.fromJson({
                    'orderId': 'OCT1',
                    'tranamt': 950,
                    'typeFrom': '2',
                    'toMerchant': '十月东区食堂',
                    'effectdateStr': '2026-10-25 17:40:00',
                  }),
                ],
                total: 4,
                pages: 2,
                currentPage: 1,
              );
            }
            return ECardTransactionPage(
              records: [
                ECardTransaction.fromJson({
                  'orderId': 'OCT2',
                  'tranamt': 10000,
                  'typeFrom': '1',
                  'turnoverType': '充值',
                  'toMerchant': '校园卡充值',
                  'effectdateStr': '2026-10-03 08:00:00',
                }),
                ECardTransaction.fromJson({
                  'orderId': 'SEP1',
                  'tranamt': 450,
                  'typeFrom': '2',
                  'toMerchant': '九月便利店',
                  'effectdateStr': '2026-09-28 20:00:00',
                }),
              ],
              total: 4,
              pages: 2,
              currentPage: 2,
            );
          },
        );

        expect(result.records.map((e) => e.orderId).toList(), ['OCT1', 'OCT2']);
        expect(result.complete, isTrue);
        expect(calls.every((c) => c['filterByAccount'] == false), isTrue);
      } finally {
        client.close(force: true);
      }
    });
  });

  group('ECardBillCacheSnapshot persistence', () {
    test('round-trips records, balanceAfter, summary and timestamps cleanly', () {
      final original = ECardBillCacheSnapshot(
        monthKey: 'ecard_bill_2026_11',
        records: [
          ECardTransaction(
            orderId: 'C1',
            amount: 13.5,
            isIncome: false,
            turnoverType: '消费',
            merchant: '银泉餐厅',
            summary: '午餐',
            dateTimeStr: '2026-11-11 12:05:00',
            dateTime: DateTime(2026, 11, 11, 12, 5, 0),
            balanceAfter: 66.5,
          ),
          ECardTransaction(
            orderId: 'C2',
            amount: 100.0,
            isIncome: true,
            turnoverType: '充值',
            merchant: '支付宝充值',
            summary: '在线充值',
            dateTimeStr: '2026-11-01 08:00:00',
            dateTime: DateTime(2026, 11, 1, 8, 0, 0),
            balanceAfter: 166.5,
          ),
        ],
        totalCount: 2,
        complete: true,
        updatedAt: DateTime(2026, 11, 12, 9, 30, 0),
        summary: const ECardMonthlySummary(expenses: 13.5, income: 100.0),
      );

      final parsed = ECardBillCacheSnapshot.tryParse(original.toJsonString());
      expect(parsed, isNotNull);
      expect(parsed!.monthKey, 'ecard_bill_2026_11');
      expect(parsed.records.length, 2);
      expect(parsed.records.first.amount, closeTo(13.5, 0.001));
      expect(parsed.records.first.isIncome, isFalse);
      expect(parsed.records.first.balanceAfter, closeTo(66.5, 0.001));
      expect(parsed.records.last.isIncome, isTrue);
      expect(parsed.records.last.amount, closeTo(100.0, 0.001));
      expect(parsed.summary?.expenses, closeTo(13.5, 0.001));
      expect(parsed.summary?.income, closeTo(100.0, 0.001));
    });
  });
}
