class StoredUserLocation {
  const StoredUserLocation({
    required this.uid,
    required this.latitude,
    required this.longitude,
    required this.geohash,
    required this.updatedAt,
  });

  final String uid;
  final double latitude;
  final double longitude;
  final String geohash;
  final DateTime updatedAt;
}

class DistanceLabel {
  const DistanceLabel({required this.text, this.kilometers});

  final String text;
  final double? kilometers;
}
