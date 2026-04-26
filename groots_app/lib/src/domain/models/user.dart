class User {
  final String id;
  final String username;
  final String email;
  final int storageQuotaBytes;
  final int usedStorageBytes;
  final bool isAdmin;

  const User({
    required this.id,
    required this.username,
    required this.email,
    required this.storageQuotaBytes,
    required this.usedStorageBytes,
    this.isAdmin = false,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        username: json['username'] as String,
        email: json['email'] as String,
        storageQuotaBytes: json['storage_quota_bytes'] as int,
        usedStorageBytes: json['used_storage_bytes'] as int,
        isAdmin: json['is_admin'] as bool? ?? false,
      );

  double get storageUsedPercent =>
      storageQuotaBytes == 0 ? 0 : usedStorageBytes / storageQuotaBytes;
}
