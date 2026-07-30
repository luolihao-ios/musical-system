class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    this.isBuiltIn = false,
  });

  static const liked = Playlist(id: 'liked', name: '我喜欢', isBuiltIn: true);

  final String id;
  final String name;
  final bool isBuiltIn;
}
