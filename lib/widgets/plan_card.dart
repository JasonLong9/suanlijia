import 'package:flutter/material.dart';

/// 套餐卡片标签类型
enum PlanTagType { hot, value, flexible, deal }

/// 套餐卡片组件
class PlanCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String price;
  final String priceUnit;
  final PlanTagType? tagType;
  final VoidCallback onTap;

  const PlanCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.priceUnit,
    this.tagType,
    required this.onTap,
  });

  String get _tagText {
    switch (tagType) {
      case PlanTagType.hot:
        return '热卖';
      case PlanTagType.value:
        return '超值';
      case PlanTagType.flexible:
        return '灵活';
      case PlanTagType.deal:
        return '划算';
      default:
        return '';
    }
  }

  Color get _tagColor {
    switch (tagType) {
      case PlanTagType.hot:
        return const Color(0xFFFF6B35);
      case PlanTagType.value:
        return const Color(0xFF4CAF50);
      case PlanTagType.flexible:
        return const Color(0xFF2196F3);
      case PlanTagType.deal:
        return const Color(0xFF9C27B0);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B2838),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2D4A5E), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行 + 标签
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (tagType != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _tagColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _tagText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          // 60fps 标签
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF2196F3).withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF2196F3), width: 1),
              ),
              child: const Text(
                '60fps',
                style: TextStyle(
                  color: Color(0xFF2196F3),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          
          // 分辨率 · 自动选择
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xFF8899A6),
                fontSize: 12,
              ),
            ),
          ),
          
          const Spacer(),
          
          // 价格
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '$price$priceUnit',
              style: const TextStyle(
                color: Color(0xFFFF6B35),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          
          // 开机按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2196F3),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('开机', style: TextStyle(fontSize: 14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
