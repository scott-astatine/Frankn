enum ProviderKind { host, node }

class CapabilityProvider {
  final ProviderKind kind;
  final String providerId;
  final String displayName;

  const CapabilityProvider({
    required this.kind,
    required this.providerId,
    required this.displayName,
  });

  factory CapabilityProvider.fromJson(Map<String, dynamic> json) {
    final kindStr = (json['kind'] as String? ?? 'host').toLowerCase();
    final providerId = json['provider_id'] as String? ??
        json['providerId'] as String? ??
        json['node_id'] as String? ??
        json['nodeId'] as String? ??
        (kindStr == 'host' ? 'host' : 'unknown');
    final displayName = json['display_name'] as String? ??
        json['displayName'] as String? ??
        json['name'] as String? ??
        providerId;

    return CapabilityProvider(
      kind: kindStr == 'host' ? ProviderKind.host : ProviderKind.node,
      providerId: providerId,
      displayName: displayName,
    );
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'provider_id': providerId,
    'display_name': displayName,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CapabilityProvider &&
          runtimeType == other.runtimeType &&
          kind == other.kind &&
          providerId == other.providerId;

  @override
  int get hashCode => kind.hashCode ^ providerId.hashCode;
}
