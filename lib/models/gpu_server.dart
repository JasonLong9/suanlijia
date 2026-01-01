/// GPU 服务器数据模型

enum ServerStatus {
  available,  // 可租赁 (绿色)
  inUse,      // 使用中 (蓝色)
  offline,    // 离线 (红色)
}

class GpuServer {
  final String id;
  final String name;
  String? remark;
  String? location;
  String? gpuModel;
  String? gpuTier;
  ServerStatus status;
  DateTime? lastOnlineTime;
  
  // BMC 配置
  String? bmcAddress;
  String? bmcUsername;
  String? bmcPassword;
  
  // 租赁信息
  String? currentLeaseId;
  String? currentUserId;
  String? currentUserName;

  GpuServer({
    required this.id,
    required this.name,
    this.remark,
    this.location,
    this.gpuModel,
    this.gpuTier,
    this.status = ServerStatus.offline,
    this.lastOnlineTime,
    this.bmcAddress,
    this.bmcUsername,
    this.bmcPassword,
    this.currentLeaseId,
    this.currentUserId,
    this.currentUserName,
  });

  factory GpuServer.fromJson(Map<String, dynamic> json) {
    return GpuServer(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      remark: json['remark'],
      location: json['location'],
      gpuModel: json['gpu_model'],
      gpuTier: json['gpu_tier'],
      status: _parseStatus(json['status']),
      lastOnlineTime: json['last_online_time'] != null
          ? DateTime.tryParse(json['last_online_time'])
          : null,
      bmcAddress: json['bmc_address'],
      bmcUsername: json['bmc_username'],
      bmcPassword: json['bmc_password'],
      currentLeaseId: json['current_lease_id'],
      currentUserId: json['current_user_id'],
      currentUserName: json['current_user_name'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'remark': remark,
      'location': location,
      'gpu_model': gpuModel,
      'gpu_tier': gpuTier,
      'status': status.name,
      'bmc_address': bmcAddress,
      'bmc_username': bmcUsername,
      'bmc_password': bmcPassword,
    };
  }

  static ServerStatus _parseStatus(String? status) {
    switch (status) {
      case 'available':
        return ServerStatus.available;
      case 'in_use':
      case 'inUse':
        return ServerStatus.inUse;
      default:
        return ServerStatus.offline;
    }
  }

  /// 获取状态显示文本
  String get statusText {
    switch (status) {
      case ServerStatus.available:
        return '可租赁';
      case ServerStatus.inUse:
        return '使用中';
      case ServerStatus.offline:
        return '离线';
    }
  }

  /// 是否已配置 BMC
  bool get hasBmcConfig => 
      bmcAddress != null && 
      bmcAddress!.isNotEmpty &&
      bmcUsername != null && 
      bmcUsername!.isNotEmpty;
}

/// 预定义的地理位置选项
const List<String> predefinedLocations = [
  '香港',
  '深圳',
  '上海',
  '北京',
  '广州',
  '新加坡',
  '东京',
  '美西',
  '美东',
];

/// 预定义的显卡型号选项
const List<String> predefinedGpuModels = [
  'RTX 4060',
  'RTX 4060 Ti',
  'RTX 4070',
  'RTX 4070 Ti',
  'RTX 4080',
  'RTX 4090',
  'RTX 3060',
  'RTX 3070',
  'RTX 3080',
  'RTX 3090',
];

/// 预定义的显卡池分类
const List<String> predefinedGpuTiers = [
  '60系',
  '70系',
  '80系',
  '90系',
];
