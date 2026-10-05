part of 'native_build_support_test.dart';

File _writeElfFixture(
  File file, {
  required NativeTargetArchitecture architecture,
  Set<String> exports = requiredDuneExports,
}) {
  final is64 =
      architecture == NativeTargetArchitecture.x64 ||
      architecture == NativeTargetArchitecture.arm64;
  final headerSize = is64 ? 64 : 52;
  final phSize = is64 ? 56 : 32;
  final shSize = is64 ? 64 : 40;
  final symSize = is64 ? 24 : 16;
  final strings = BytesBuilder()..addByte(0);
  final names = <int>[];
  for (final name in exports) {
    names.add(strings.length);
    strings.add([...ascii.encode(name), 0]);
  }
  final strtab = strings.toBytes();
  final count = exports.length + 1;
  const symOffset = 0x400;
  final strOffset = symOffset + count * symSize;
  final shOffset = (strOffset + strtab.length + 7) & ~7;
  final bytes = Uint8List(shOffset + 4 * shSize);
  final data = ByteData.sublistView(bytes);
  void u16(int offset, int value) =>
      data.setUint16(offset, value, Endian.little);
  void u32(int offset, int value) =>
      data.setUint32(offset, value, Endian.little);
  void word(int offset, int value) {
    if (is64) {
      data.setUint64(offset, value, Endian.little);
    } else {
      u32(offset, value);
    }
  }

  bytes.setAll(0, [0x7f, 0x45, 0x4c, 0x46, is64 ? 2 : 1, 1, 1]);
  u16(16, 3);
  u16(18, switch (architecture) {
    NativeTargetArchitecture.ia32 => 3,
    NativeTargetArchitecture.arm => 40,
    NativeTargetArchitecture.x64 => 62,
    NativeTargetArchitecture.arm64 => 183,
  });
  u32(20, 1);
  word(is64 ? 32 : 28, headerSize);
  word(is64 ? 40 : 32, shOffset);
  u16(is64 ? 52 : 40, headerSize);
  u16(is64 ? 54 : 42, phSize);
  u16(is64 ? 56 : 44, 2);
  u16(is64 ? 58 : 46, shSize);
  u16(is64 ? 60 : 48, 4);
  void program(int index, int type, int offset, int size, int flags) {
    final start = headerSize + index * phSize;
    u32(start, type);
    u32(start + (is64 ? 4 : 24), flags);
    word(start + (is64 ? 8 : 4), offset);
    word(start + (is64 ? 16 : 8), offset);
    word(start + (is64 ? 32 : 16), size);
    word(start + (is64 ? 40 : 20), size);
    word(start + (is64 ? 48 : 28), type == 1 ? 0x1000 : (is64 ? 8 : 4));
  }

  program(0, 1, 0, bytes.length, 7);
  program(1, 2, 0x120, 6 * (is64 ? 16 : 8), 6);
  bytes[0x100] = 0xc3;
  final tags = <(int, int)>[
    (5, strOffset),
    (6, symOffset),
    (10, strtab.length),
    (11, symSize),
    (4, 0x200),
    (0, 0),
  ];
  for (var i = 0; i < tags.length; i++) {
    final offset = 0x120 + i * (is64 ? 16 : 8);
    word(offset, tags[i].$1);
    word(offset + (is64 ? 8 : 4), tags[i].$2);
  }
  u32(0x200, 1);
  u32(0x204, count);
  u32(0x208, exports.isEmpty ? 0 : 1);
  for (var i = 1; i < count - 1; i++) {
    u32(0x20c + i * 4, i + 1);
  }
  for (var i = 0; i < names.length; i++) {
    final offset = symOffset + (i + 1) * symSize;
    u32(offset, names[i]);
    bytes[offset + (is64 ? 4 : 12)] = 0x12;
    u16(offset + (is64 ? 6 : 14), 3);
    word(offset + (is64 ? 8 : 4), 0x100);
  }
  bytes.setAll(strOffset, strtab);
  void section(
    int index,
    int type,
    int offset,
    int size,
    int flags,
    int link,
    int entrySize,
  ) {
    final start = shOffset + index * shSize;
    u32(start + 4, type);
    word(start + 8, flags);
    word(start + (is64 ? 16 : 12), offset);
    word(start + (is64 ? 24 : 16), offset);
    word(start + (is64 ? 32 : 20), size);
    u32(start + (is64 ? 40 : 24), link);
    word(start + (is64 ? 48 : 32), is64 ? 8 : 4);
    word(start + (is64 ? 56 : 36), entrySize);
  }

  section(1, 11, symOffset, count * symSize, 2, 2, symSize);
  section(2, 3, strOffset, strtab.length, 2, 0, 0);
  section(3, 1, 0x100, 1, 6, 0, 0);
  file.writeAsBytesSync(bytes);
  return file;
}

File _writeMachOFixture(
  File file, {
  Set<String> exports = requiredDuneExports,
  int platform = 1,
}) {
  final names = exports.map((name) => ascii.encode('_$name')).toList();
  final rootSize = 2 + names.fold<int>(0, (sum, name) => sum + name.length + 3);
  final trie = BytesBuilder()..add([0, names.length]);
  for (var i = 0; i < names.length; i++) {
    final offset = rootSize + i * 5;
    trie.add([...names[i], 0, (offset & 0x7f) | 0x80, offset >> 7]);
  }
  for (var i = 0; i < names.length; i++) {
    trie.add([3, 0, 0x80, 2, 0]);
  }
  final trieBytes = trie.toBytes();
  final bytes = Uint8List(0x200 + trieBytes.length);
  final data = ByteData.sublistView(bytes);
  void u32(int offset, int value) =>
      data.setUint32(offset, value, Endian.little);
  u32(0, 0xfeedfacf);
  u32(4, 0x0100000c);
  u32(12, 6);
  u32(16, 4);
  u32(20, 152);
  u32(32, 0x19);
  u32(36, 72);
  data.setUint64(64, bytes.length, Endian.little);
  data.setUint64(80, bytes.length, Endian.little);
  u32(88, 7);
  u32(92, 5);
  u32(104, 0xd);
  u32(108, 40);
  u32(112, 24);
  bytes.setAll(128, ascii.encode('@rpath/test\x00'));
  u32(144, 0x32);
  u32(148, 24);
  u32(152, platform);
  u32(168, 0x80000033);
  u32(172, 16);
  u32(176, 0x200);
  u32(180, trieBytes.length);
  bytes.setAll(0x100, [0xc0, 0x03, 0x5f, 0xd6]);
  bytes.setAll(0x200, trieBytes);
  file.writeAsBytesSync(bytes);
  return file;
}

File _writePeFixture(File file, {Set<String> exports = requiredDuneExports}) {
  final names = exports.toList()..sort();
  final namesBytes = BytesBuilder();
  final offsets = <int>[];
  for (final name in names) {
    offsets.add(namesBytes.length);
    namesBytes.add([...ascii.encode(name), 0]);
  }
  const exportOffset = 0x400;
  final namesStart = 40 + names.length * 10;
  final exportSize = namesStart + namesBytes.length;
  final rawSize = (exportSize + 0x1ff) & ~0x1ff;
  final bytes = Uint8List(exportOffset + rawSize);
  final data = ByteData.sublistView(bytes);
  void u16(int offset, int value) =>
      data.setUint16(offset, value, Endian.little);
  void u32(int offset, int value) =>
      data.setUint32(offset, value, Endian.little);
  u16(0, 0x5a4d);
  u32(60, 64);
  u32(64, 0x4550);
  u16(68, 0x8664);
  u16(70, 2);
  u16(84, 240);
  u16(86, 0x2002);
  const optional = 88;
  u16(optional, 0x20b);
  u32(optional + 32, 0x1000);
  u32(optional + 36, 0x200);
  u32(optional + 56, 0x4000);
  u32(optional + 60, 0x200);
  u32(optional + 108, 16);
  u32(optional + 112, 0x2000);
  u32(optional + 116, exportSize);
  void section(int offset, int address, int fileOffset, int size, int flags) {
    u32(offset + 8, size);
    u32(offset + 12, address);
    u32(offset + 16, size);
    u32(offset + 20, fileOffset);
    u32(offset + 36, flags);
  }

  section(328, 0x1000, 0x200, 0x200, 0x60000020);
  section(368, 0x2000, exportOffset, rawSize, 0x40000040);
  bytes[0x200] = 0xc3;
  u32(exportOffset + 16, 1);
  u32(exportOffset + 20, names.length);
  u32(exportOffset + 24, names.length);
  u32(exportOffset + 28, 0x2000 + 40);
  u32(exportOffset + 32, 0x2000 + 40 + names.length * 4);
  u32(exportOffset + 36, 0x2000 + 40 + names.length * 8);
  for (var i = 0; i < names.length; i++) {
    u32(exportOffset + 40 + i * 4, 0x1000);
    u32(
      exportOffset + 40 + names.length * 4 + i * 4,
      0x2000 + namesStart + offsets[i],
    );
    u16(exportOffset + 40 + names.length * 8 + i * 2, i);
  }
  bytes.setAll(exportOffset + namesStart, namesBytes.toBytes());
  file.writeAsBytesSync(bytes);
  return file;
}
