import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'app_database.g.dart';

@DataClassName('TrackRecord')
class Tracks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get artist => text().withDefault(const Constant('未知歌手'))();
  TextColumn get album => text().nullable()();
  TextColumn get uri => text().nullable()();
  IntColumn get source => integer()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  TextColumn get artworkPath => text().nullable()();
  TextColumn get lyricPath => text().nullable()();
  BoolColumn get isLiked => boolean().withDefault(const Constant(false))();
  DateTimeColumn get importedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastPlayedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('PlaylistRecord')
class Playlists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  BoolColumn get isBuiltIn => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PlaylistEntries extends Table {
  TextColumn get playlistId => text().references(Playlists, #id)();
  TextColumn get trackId => text().references(Tracks, #id)();
  IntColumn get position => integer()();

  @override
  Set<Column<Object>> get primaryKey => {playlistId, trackId};
}

class ScanRoots extends Table {
  TextColumn get path => text()();
  DateTimeColumn get lastScannedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {path};
}

class Preferences extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(
  tables: [Tracks, Playlists, PlaylistEntries, ScanRoots, Preferences],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.inMemory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;
}
