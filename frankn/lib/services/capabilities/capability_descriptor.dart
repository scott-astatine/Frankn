class CapabilityDescriptor {
  final String id;
  final String name;
  final String version;
  final List<String> actions;
  final Map<String, dynamic> properties;
  final List<String> events;
  final Map<String, dynamic> schemas;

  const CapabilityDescriptor({
    required this.id,
    required this.name,
    this.version = '1.0.0',
    this.actions = const [],
    this.properties = const {},
    this.events = const [],
    this.schemas = const {},
  });

  factory CapabilityDescriptor.fromJson(Map<String, dynamic> json) {
    return CapabilityDescriptor(
      id: json['id'] as String? ?? json['capability'] as String? ?? 'unknown',
      name: json['name'] as String? ?? json['id'] as String? ?? json['capability'] as String? ?? 'Capability',
      version: json['version'] as String? ?? '1.0.0',
      actions: (json['actions'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      properties: (json['properties'] as Map?)?.map((k, v) => MapEntry(k.toString(), v)) ?? const {},
      events: (json['events'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      schemas: (json['schemas'] as Map?)?.map((k, v) => MapEntry(k.toString(), v)) ?? const {},
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'version': version,
    'actions': actions,
    'properties': properties,
    'events': events,
    'schemas': schemas,
  };
}
