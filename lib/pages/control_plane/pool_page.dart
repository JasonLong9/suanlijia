import 'package:flutter/material.dart';

import '../../control_plane/control_plane_controller.dart';
import '../../control_plane/control_plane_models.dart';
import '../../service_locator.dart';
import '../../widgets/plan_card.dart';

/// 深色主题颜色常量
class PoolPageColors {
  static const Color bgDark = Color(0xFF0D1B2A);
  static const Color cardDark = Color(0xFF1B2838);
  static const Color accentOrange = Color(0xFFFF6B35);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFF8899A6);
  static const Color borderColor = Color(0xFF2D4A5E);
}

/// 套餐数据模型
class RentalPlan {
  final String id;
  final String title;
  final String subtitle;
  final String price;
  final String priceUnit;
  final PlanTagType? tag;
  final int hours; // 0 表示按小时，-1 表示包周
  
  const RentalPlan({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.priceUnit,
    this.tag,
    required this.hours,
  });
}

class PoolPage extends StatefulWidget {
  const PoolPage({super.key});

  @override
  State<PoolPage> createState() => _PoolPageState();
}

class _PoolPageState extends State<PoolPage> {
  String? _selectedRegion;
  String? _selectedGpuTier;
  bool _isLoading = false;

  // 60系显卡套餐
  final List<RentalPlan> _tier60Plans = const [
    RentalPlan(
      id: '60_100h',
      title: '100小时版',
      subtitle: '分辨率 · 自动选择',
      price: '100小时',
      priceUnit: '',
      tag: PlanTagType.hot,
      hours: 100,
    ),
    RentalPlan(
      id: '60_300h',
      title: '300小时版',
      subtitle: '分辨率 · 自动选择',
      price: '300小时',
      priceUnit: '',
      tag: PlanTagType.value,
      hours: 300,
    ),
    RentalPlan(
      id: '60_hourly',
      title: '按小时租赁',
      subtitle: '分辨率 · 自动选择',
      price: '2.5元',
      priceUnit: '/小时',
      tag: PlanTagType.flexible,
      hours: 0,
    ),
    RentalPlan(
      id: '60_weekly',
      title: '包周租赁',
      subtitle: '分辨率 · 自动选择',
      price: '200元',
      priceUnit: '/周',
      tag: PlanTagType.deal,
      hours: -1,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshPool();
    });
  }

  Future<void> _refreshPool() async {
    setState(() => _isLoading = true);
    try {
      await getIt<ControlPlaneController>().refreshPool(
        region: _selectedRegion,
        gpuTier: _selectedGpuTier,
        status: NodeStatus.free,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onPlanTap(RentalPlan plan) async {
    // TODO: 实现套餐选择和租赁流程
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('选择了: ${plan.title}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PoolPageColors.bgDark,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部标题栏
            _buildHeader(),
            
            // 灵活计费方案 Banner
            _buildFlexiblePlanBanner(),
            
            // 主内容区
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshPool,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 60系显卡分类
                      _buildGpuCategory(
                        title: '60系显卡',
                        subtitle: 'RTX 4060 · 8GB显存',
                        plans: _tier60Plans,
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // 可以添加更多 GPU 分类...
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // 品牌 Logo
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B35), Color(0xFFFF8C5A)],
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              '算力橙',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          
          const Spacer(),
          
          // 刷新按钮
          IconButton(
            icon: _isLoading 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh, color: Colors.white),
            onPressed: _isLoading ? null : _refreshPool,
          ),
        ],
      ),
    );
  }

  Widget _buildFlexiblePlanBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6B35), Color(0xFFFF8C5A)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF6B35).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Column(
        children: [
          Text(
            '灵活计费方案',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 4),
          Text(
            '按需租赁，轻济实惠',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGpuCategory({
    required String title,
    required String subtitle,
    required List<RentalPlan> plans,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 分类标题
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: PoolPageColors.accentOrange,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                color: PoolPageColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              subtitle,
              style: const TextStyle(
                color: PoolPageColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        // 套餐卡片网格
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.85,
          ),
          itemCount: plans.length,
          itemBuilder: (context, index) {
            final plan = plans[index];
            return PlanCard(
              title: plan.title,
              subtitle: plan.subtitle,
              price: plan.price,
              priceUnit: plan.priceUnit,
              tagType: plan.tag,
              onTap: () => _onPlanTap(plan),
            );
          },
        ),
      ],
    );
  }
}
