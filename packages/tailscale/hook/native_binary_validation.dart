part of 'native_build_support.dart';

class _BinaryReader {
  _BinaryReader(this.file, this.length, this.path);

  final RandomAccessFile file;
  final int length;
  final String path;

  Never fail(String reason) => throw NativeBuildException('$reason: $path');

  void bounds(int offset, int size, [String label = 'Binary table']) {
    if (offset < 0 || size < 0 || offset > length || size > length - offset) {
      fail('$label is truncated or out of bounds');
    }
  }

  ByteData read(int offset, int size) {
    bounds(offset, size);
    file.setPositionSync(offset);
    final bytes = file.readSync(size);
    if (bytes.length != size) fail('Binary changed during validation');
    return ByteData.sublistView(bytes);
  }
}

int _u16(ByteData data, int offset) => data.getUint16(offset, Endian.little);
int _u32(ByteData data, int offset) => data.getUint32(offset, Endian.little);
int _u64(ByteData data, int offset) => data.getUint64(offset, Endian.little);

String _stringAt(_BinaryReader reader, ByteData table, int offset) {
  if (offset < 0 || offset >= table.lengthInBytes) {
    reader.fail('String table index is out of bounds');
  }
  var end = offset;
  while (end < table.lengthInBytes && table.getUint8(end) != 0) {
    end++;
  }
  if (end == table.lengthInBytes) reader.fail('Unterminated symbol name');
  return latin1.decode(
    table.buffer.asUint8List(table.offsetInBytes + offset, end - offset),
  );
}

class _MappedRegion {
  const _MappedRegion(this.offset, this.address, this.size, this.executable);

  final int offset;
  final int address;
  final int size;
  final bool executable;

  bool contains(int value, int count) =>
      value >= address &&
      count >= 0 &&
      value - address <= size &&
      count <= size - (value - address);
}

int _mappedOffset(
  _BinaryReader reader,
  List<_MappedRegion> regions,
  int address,
  int size,
) {
  final matches = regions
      .where((region) => region.contains(address, size))
      .toList();
  if (matches.length != 1) {
    reader.fail('Address is not uniquely mapped to file data');
  }
  return matches.single.offset + address - matches.single.address;
}

bool _executableAddress(List<_MappedRegion> regions, int address) =>
    regions.any((region) => region.executable && region.contains(address, 1));

Set<String> _elfExports(_BinaryReader reader, NativeBuildTarget target) {
  final ident = reader.read(0, 16);
  if (_u32(ident, 0) != 0x464c457f) {
    reader.fail('Native artifact is not an ELF binary');
  }
  final is64 =
      target.architecture == NativeTargetArchitecture.x64 ||
      target.architecture == NativeTargetArchitecture.arm64;
  if (ident.getUint8(4) != (is64 ? 2 : 1)) {
    reader.fail('ELF class does not match target $target');
  }
  if (ident.getUint8(5) != 1 || ident.getUint8(6) != 1) {
    reader.fail('Unsupported ELF encoding');
  }
  final headerSize = is64 ? 64 : 52;
  final header = reader.read(0, headerSize);
  final expectedMachine = switch (target.architecture) {
    NativeTargetArchitecture.ia32 => 3,
    NativeTargetArchitecture.arm => 40,
    NativeTargetArchitecture.x64 => 62,
    NativeTargetArchitecture.arm64 => 183,
  };
  if (_u16(header, 18) != expectedMachine) {
    reader.fail('ELF machine does not match target $target');
  }
  if (_u16(header, 16) != 3 ||
      _u32(header, 20) != 1 ||
      _u16(header, is64 ? 52 : 40) != headerSize) {
    reader.fail('ELF artifact is not a shared library');
  }
  final phoff = is64 ? _u64(header, 32) : _u32(header, 28);
  final phsize = _u16(header, is64 ? 54 : 42);
  final phcount = _u16(header, is64 ? 56 : 44);
  if (phcount == 0 || phsize != (is64 ? 56 : 32) || phoff < headerSize) {
    reader.fail('Invalid ELF program table');
  }
  reader.bounds(phoff, phsize * phcount, 'ELF program table');
  final loads = <_MappedRegion>[];
  ByteData? dynamicData;
  int? dynamicOffset;
  int? dynamicAddress;
  for (var i = 0; i < phcount; i++) {
    final ph = reader.read(phoff + i * phsize, phsize);
    final type = _u32(ph, 0);
    final offset = is64 ? _u64(ph, 8) : _u32(ph, 4);
    final address = is64 ? _u64(ph, 16) : _u32(ph, 8);
    final size = is64 ? _u64(ph, 32) : _u32(ph, 16);
    final memorySize = is64 ? _u64(ph, 40) : _u32(ph, 20);
    final flags = _u32(ph, is64 ? 4 : 24);
    final alignment = is64 ? _u64(ph, 48) : _u32(ph, 28);
    reader.bounds(offset, size, 'ELF segment');
    if (type == 1) {
      if (memorySize < size ||
          (alignment > 1 &&
              ((alignment & (alignment - 1)) != 0 ||
                  offset % alignment != address % alignment))) {
        reader.fail('Invalid ELF load segment');
      }
      loads.add(_MappedRegion(offset, address, size, flags & 1 != 0));
    } else if (type == 2) {
      if (dynamicData != null || size == 0 || size % (is64 ? 16 : 8) != 0) {
        reader.fail('Invalid ELF dynamic segment');
      }
      dynamicData = reader.read(offset, size);
      dynamicOffset = offset;
      dynamicAddress = address;
    }
  }
  if (loads.isEmpty ||
      !loads.any((region) => region.executable) ||
      dynamicData == null) {
    reader.fail('ELF load or dynamic segment is missing');
  }
  if (_mappedOffset(
        reader,
        loads,
        dynamicAddress!,
        dynamicData.lengthInBytes,
      ) !=
      dynamicOffset) {
    reader.fail('ELF dynamic segment is not loaded');
  }
  final dynamic = <int, int>{};
  var terminated = false;
  for (
    var offset = 0;
    offset < dynamicData.lengthInBytes;
    offset += is64 ? 16 : 8
  ) {
    final tag = is64 ? _u64(dynamicData, offset) : _u32(dynamicData, offset);
    if (tag == 0) {
      terminated = true;
      break;
    }
    dynamic[tag] = is64
        ? _u64(dynamicData, offset + 8)
        : _u32(dynamicData, offset + 4);
  }
  if (!terminated ||
      !dynamic.containsKey(5) ||
      !dynamic.containsKey(6) ||
      !dynamic.containsKey(10) ||
      dynamic[11] != (is64 ? 24 : 16) ||
      (!dynamic.containsKey(4) && !dynamic.containsKey(0x6ffffef5))) {
    reader.fail('ELF dynamic symbol metadata is incomplete');
  }

  final shoff = is64 ? _u64(header, 40) : _u32(header, 32);
  final shsize = _u16(header, is64 ? 58 : 46);
  final shcount = _u16(header, is64 ? 60 : 48);
  if (shoff < headerSize || shcount == 0 || shsize != (is64 ? 64 : 40)) {
    reader.fail('ELF section table is missing or unsupported');
  }
  reader.bounds(shoff, shsize * shcount, 'ELF section table');
  final sections = <ByteData>[];
  int sectionOffset(ByteData section) =>
      is64 ? _u64(section, 24) : _u32(section, 16);
  int sectionSize(ByteData section) =>
      is64 ? _u64(section, 32) : _u32(section, 20);
  int sectionAddress(ByteData section) =>
      is64 ? _u64(section, 16) : _u32(section, 12);
  for (var i = 0; i < shcount; i++) {
    final section = reader.read(shoff + i * shsize, shsize);
    if (_u32(section, 4) != 8) {
      reader.bounds(
        sectionOffset(section),
        sectionSize(section),
        'ELF section',
      );
    }
    sections.add(section);
  }
  final dynsyms = sections.where((section) => _u32(section, 4) == 11).toList();
  if (dynsyms.length != 1) {
    reader.fail('ELF must have one dynamic symbol table');
  }
  final symbols = dynsyms.single;
  final stringIndex = _u32(symbols, is64 ? 40 : 24);
  final entrySize = is64 ? _u64(symbols, 56) : _u32(symbols, 36);
  if (stringIndex >= shcount ||
      entrySize != dynamic[11] ||
      sectionSize(symbols) % entrySize != 0) {
    reader.fail('Invalid ELF dynamic symbol table');
  }
  final strings = sections[stringIndex];
  if (_u32(strings, 4) != 3 ||
      sectionAddress(symbols) != dynamic[6] ||
      sectionAddress(strings) != dynamic[5] ||
      sectionSize(strings) != dynamic[10] ||
      _mappedOffset(reader, loads, dynamic[6]!, sectionSize(symbols)) !=
          sectionOffset(symbols) ||
      _mappedOffset(reader, loads, dynamic[5]!, sectionSize(strings)) !=
          sectionOffset(strings)) {
    reader.fail('ELF dynamic tables do not match loaded metadata');
  }
  final strtab = reader.read(sectionOffset(strings), sectionSize(strings));
  final symtab = reader.read(sectionOffset(symbols), sectionSize(symbols));
  final symbolCount = symtab.lengthInBytes ~/ entrySize;
  late final bool Function(String, int) reachable;
  if (!dynamic.containsKey(0x6ffffef5)) {
    final hashOffset = _mappedOffset(reader, loads, dynamic[4]!, 8);
    final hash = reader.read(hashOffset, 8);
    final buckets = _u32(hash, 0);
    if (buckets == 0 || _u32(hash, 4) != symbolCount) {
      reader.fail('Invalid ELF dynamic hash table');
    }
    final size = 8 + 4 * (buckets + symbolCount);
    _mappedOffset(reader, loads, dynamic[4]!, size);
    final table = reader.read(hashOffset, size);
    reachable = (name, symbol) {
      var hash = 0;
      for (final byte in name.codeUnits) {
        hash = (hash << 4) + byte;
        final high = hash & 0xf0000000;
        hash = (hash ^ (high >> 24)) & ~high;
      }
      var index = _u32(table, 8 + (hash % buckets) * 4);
      for (var steps = 0; index != 0 && steps < symbolCount; steps++) {
        if (index >= symbolCount) {
          reader.fail('ELF hash index is out of bounds');
        }
        if (index == symbol) return true;
        index = _u32(table, 8 + buckets * 4 + index * 4);
      }
      return false;
    };
  } else {
    final hashOffset = _mappedOffset(reader, loads, dynamic[0x6ffffef5]!, 16);
    final hash = reader.read(hashOffset, 16);
    final buckets = _u32(hash, 0);
    final start = _u32(hash, 4);
    final bloom = _u32(hash, 8);
    final bloomShift = _u32(hash, 12);
    if (buckets == 0 ||
        bloom == 0 ||
        bloom & (bloom - 1) != 0 ||
        start > symbolCount ||
        bloomShift >= 32) {
      reader.fail('Invalid ELF GNU hash table');
    }
    final size =
        16 + bloom * (is64 ? 8 : 4) + buckets * 4 + (symbolCount - start) * 4;
    _mappedOffset(reader, loads, dynamic[0x6ffffef5]!, size);
    final table = reader.read(hashOffset, size);
    reachable = (name, symbol) {
      var hash = 5381;
      for (final byte in name.codeUnits) {
        hash = (hash * 33 + byte) & 0xffffffff;
      }
      final wordBits = is64 ? 64 : 32;
      final bloomOffset = 16 + ((hash ~/ wordBits) % bloom) * (is64 ? 8 : 4);
      final word = is64 ? _u64(table, bloomOffset) : _u32(table, bloomOffset);
      final mask =
          (1 << (hash % wordBits)) | (1 << ((hash >> bloomShift) % wordBits));
      if (word & mask != mask) return false;
      final bucketOffset = 16 + bloom * (is64 ? 8 : 4);
      var index = _u32(table, bucketOffset + (hash % buckets) * 4);
      if (index == 0) return false;
      if (index < start || index >= symbolCount) {
        reader.fail('ELF GNU hash index is out of bounds');
      }
      while (index < symbolCount) {
        final chain = _u32(
          table,
          bucketOffset + buckets * 4 + (index - start) * 4,
        );
        if (index == symbol && (chain | 1) == (hash | 1)) return true;
        if (chain & 1 != 0) return false;
        index++;
      }
      reader.fail('Unterminated ELF GNU hash chain');
    };
  }
  ByteData? versions;
  if (dynamic.containsKey(0x6ffffff0)) {
    versions = reader.read(
      _mappedOffset(reader, loads, dynamic[0x6ffffff0]!, symbolCount * 2),
      symbolCount * 2,
    );
  }
  final exports = <String>{};
  for (var i = 0; i < symbolCount; i++) {
    final offset = i * entrySize;
    final info = symtab.getUint8(offset + (is64 ? 4 : 12));
    final visibility = symtab.getUint8(offset + (is64 ? 5 : 13)) & 3;
    final section = _u16(symtab, offset + (is64 ? 6 : 14));
    final value = is64 ? _u64(symtab, offset + 8) : _u32(symtab, offset + 4);
    final name = _stringAt(reader, strtab, _u32(symtab, offset));
    if ((info >> 4 == 1 || info >> 4 == 2) &&
        info & 15 == 2 &&
        (visibility == 0 || visibility == 3) &&
        section > 0 &&
        section < shcount &&
        (versions == null ||
            (_u16(versions, i * 2) & 0x8000 == 0 &&
                _u16(versions, i * 2) != 0)) &&
        _executableAddress(loads, value) &&
        reachable(name, i)) {
      exports.add(name);
    }
  }
  return exports;
}

Set<String> _machOExports(_BinaryReader reader, NativeBuildTarget target) {
  final header = reader.read(0, 32);
  final is64 =
      target.architecture == NativeTargetArchitecture.x64 ||
      target.architecture == NativeTargetArchitecture.arm64;
  if (!is64 || _u32(header, 0) != 0xfeedfacf) {
    reader.fail('Only thin 64-bit Mach-O dylibs are supported');
  }
  final cpu = target.architecture == NativeTargetArchitecture.arm64
      ? 0x0100000c
      : 0x01000007;
  if (_u32(header, 4) != cpu) {
    reader.fail('Mach-O CPU type does not match target $target');
  }
  if (_u32(header, 12) != 6) reader.fail('Mach-O artifact is not a dylib');
  final count = _u32(header, 16);
  final commandsSize = _u32(header, 20);
  if (count == 0 || commandsSize < count * 8) {
    reader.fail('Invalid Mach-O load commands');
  }
  reader.bounds(32, commandsSize, 'Mach-O load commands');
  final segments = <_MappedRegion>[];
  int? platform;
  int? exportOffset;
  int? exportSize;
  var hasId = false;
  var offset = 32;
  for (var i = 0; i < count; i++) {
    if (offset + 8 > 32 + commandsSize) {
      reader.fail('Mach-O command header is truncated');
    }
    final prefix = reader.read(offset, 8);
    final type = _u32(prefix, 0);
    final size = _u32(prefix, 4);
    if (size < 8 || size % 8 != 0 || size > 32 + commandsSize - offset) {
      reader.fail('Invalid Mach-O command size');
    }
    final command = reader.read(offset, size);
    if (type == 0x19) {
      if (size < 72 || size != 72 + _u32(command, 64) * 80) {
        reader.fail('Invalid Mach-O segment command');
      }
      final address = _u64(command, 24);
      final memorySize = _u64(command, 32);
      final fileOffset = _u64(command, 40);
      final fileSize = _u64(command, 48);
      reader.bounds(fileOffset, fileSize, 'Mach-O segment');
      if (fileSize > memorySize) reader.fail('Invalid Mach-O segment size');
      segments.add(
        _MappedRegion(
          fileOffset,
          address,
          fileSize,
          _u32(command, 60) & 4 != 0,
        ),
      );
      for (var section = 72; section < size; section += 80) {
        final sectionAddress = _u64(command, section + 32);
        final sectionSize = _u64(command, section + 40);
        final sectionOffset = _u32(command, section + 48);
        final sectionType = _u32(command, section + 64) & 0xff;
        if (sectionAddress < address ||
            sectionSize > memorySize ||
            sectionAddress - address > memorySize - sectionSize) {
          reader.fail('Mach-O section is outside its segment');
        }
        if (sectionType != 1 && sectionType != 12 && sectionType != 18) {
          reader.bounds(sectionOffset, sectionSize, 'Mach-O section');
          if (sectionOffset < fileOffset ||
              sectionSize > fileSize ||
              sectionOffset - fileOffset > fileSize - sectionSize) {
            reader.fail('Mach-O section data is outside its segment');
          }
        }
        reader.bounds(
          _u32(command, section + 56),
          _u32(command, section + 60) * 8,
          'Mach-O relocations',
        );
      }
    } else if (type == 0x32) {
      if (size < 24 || size != 24 + _u32(command, 20) * 8 || platform != null) {
        reader.fail('Invalid or duplicate Mach-O platform command');
      }
      platform = _u32(command, 8);
    } else if (type == 0x24 || type == 0x25) {
      if (size != 16 || platform != null) {
        reader.fail('Invalid or duplicate Mach-O version command');
      }
      platform = type == 0x24 ? 1 : (cpu == 0x01000007 ? 7 : 2);
    } else if (type == 0xd) {
      if (size < 24 || _u32(command, 8) < 24) {
        reader.fail('Invalid Mach-O dylib identity');
      }
      _stringAt(reader, command, _u32(command, 8));
      hasId = true;
    } else if (type == 0x80000033 || type == 0x80000022 || type == 0x22) {
      final trie = type == 0x80000033;
      if (size != (trie ? 16 : 48) || exportOffset != null) {
        reader.fail('Invalid or duplicate Mach-O export command');
      }
      exportOffset = _u32(command, trie ? 8 : 40);
      exportSize = _u32(command, trie ? 12 : 44);
      if (!trie) {
        for (var field = 8; field < 40; field += 8) {
          reader.bounds(
            _u32(command, field),
            _u32(command, field + 4),
            'Mach-O dyld data',
          );
        }
      }
    } else if (type == 2) {
      if (size != 24) reader.fail('Invalid Mach-O symbol command');
      reader.bounds(
        _u32(command, 8),
        _u32(command, 12) * 16,
        'Mach-O symbol table',
      );
      reader.bounds(
        _u32(command, 16),
        _u32(command, 20),
        'Mach-O string table',
      );
    }
    offset += size;
  }
  if (offset != 32 + commandsSize) {
    reader.fail('Mach-O load command count does not match size');
  }
  final expectedPlatform =
      target.operatingSystem == NativeTargetOperatingSystem.macOS
      ? 1
      : (target.isIOSSimulator ? 7 : 2);
  if (platform != expectedPlatform) {
    reader.fail(
      'Mach-O platform $platform does not match target $target (expected $expectedPlatform)',
    );
  }
  if (!hasId ||
      segments.isEmpty ||
      exportOffset == null ||
      exportSize == null ||
      exportSize == 0) {
    reader.fail('Mach-O dylib load/export metadata is incomplete');
  }
  final bases = segments
      .where(
        (segment) => segment.offset == 0 && segment.size >= 32 + commandsSize,
      )
      .toList();
  if (bases.length != 1 ||
      !segments.any(
        (segment) =>
            exportOffset! >= segment.offset &&
            exportSize! <= segment.size &&
            exportOffset - segment.offset <= segment.size - exportSize,
      )) {
    reader.fail('Mach-O header or exports are not mapped');
  }
  final base = bases.single.address;
  final trie = reader.read(exportOffset, exportSize);
  final exports = <String>{};
  final pending = <(int, String)>[(0, '')];
  final visited = <int>{};
  while (pending.isNotEmpty) {
    final (node, prefix) = pending.removeLast();
    if (!visited.add(node) || prefix.length > 4096) {
      reader.fail('Cyclic or oversized Mach-O export trie');
    }
    var cursor = node;
    int uleb() {
      var value = 0;
      for (var shift = 0; shift < 63; shift += 7) {
        if (cursor < 0 || cursor >= trie.lengthInBytes) {
          reader.fail('Truncated Mach-O export trie');
        }
        final byte = trie.getUint8(cursor++);
        value |= (byte & 0x7f) << shift;
        if (byte & 0x80 == 0) return value;
      }
      reader.fail('Invalid Mach-O export integer');
    }

    final terminalSize = uleb();
    final terminalEnd = cursor + terminalSize;
    if (terminalEnd >= trie.lengthInBytes) {
      reader.fail('Mach-O export terminal is truncated');
    }
    if (terminalSize > 0) {
      final flags = uleb();
      if (flags & 0x08 == 0 && flags & 3 == 0) {
        final address = uleb();
        if (flags & 0x10 != 0) uleb();
        if (cursor != terminalEnd) {
          reader.fail('Invalid Mach-O export terminal');
        }
        if (prefix.startsWith('_') &&
            _executableAddress(segments, base + address)) {
          exports.add(prefix.substring(1));
        }
      }
    }
    cursor = terminalEnd;
    final children = trie.getUint8(cursor++);
    for (var child = 0; child < children; child++) {
      final suffix = _stringAt(reader, trie, cursor);
      if (suffix.isEmpty) reader.fail('Empty Mach-O export edge');
      cursor += suffix.length + 1;
      final childOffset = uleb();
      pending.add((childOffset, '$prefix$suffix'));
    }
  }
  return exports;
}

Set<String> _peExports(_BinaryReader reader, NativeBuildTarget target) {
  final dos = reader.read(0, 64);
  if (_u16(dos, 0) != 0x5a4d) reader.fail('Native artifact is not a PE binary');
  final peOffset = _u32(dos, 60);
  if (peOffset < 64) reader.fail('Invalid PE header offset');
  final header = reader.read(peOffset, 24);
  if (_u32(header, 0) != 0x4550) reader.fail('Invalid PE signature');
  final machine = switch (target.architecture) {
    NativeTargetArchitecture.ia32 => 0x14c,
    NativeTargetArchitecture.arm => 0x1c4,
    NativeTargetArchitecture.x64 => 0x8664,
    NativeTargetArchitecture.arm64 => 0xaa64,
  };
  if (_u16(header, 4) != machine) {
    reader.fail('PE machine does not match target $target');
  }
  final count = _u16(header, 6);
  final optionalSize = _u16(header, 20);
  final is64 =
      target.architecture == NativeTargetArchitecture.x64 ||
      target.architecture == NativeTargetArchitecture.arm64;
  final directoryStart = is64 ? 112 : 96;
  if (count == 0 ||
      optionalSize < directoryStart + 8 ||
      _u16(header, 22) & 0x2002 != 0x2002) {
    reader.fail('PE artifact is not a complete DLL');
  }
  final optional = reader.read(peOffset + 24, optionalSize);
  if (_u16(optional, 0) != (is64 ? 0x20b : 0x10b)) {
    reader.fail('PE class does not match target $target');
  }
  final directoryCount = _u32(optional, directoryStart - 4);
  if (directoryCount == 0 ||
      directoryCount > (optionalSize - directoryStart) ~/ 8) {
    reader.fail('Invalid PE data directory count');
  }
  final imageSize = _u32(optional, 56);
  final headersSize = _u32(optional, 60);
  final sectionAlignment = _u32(optional, 32);
  final fileAlignment = _u32(optional, 36);
  final sectionOffset = peOffset + 24 + optionalSize;
  if (sectionAlignment == 0 ||
      fileAlignment == 0 ||
      sectionAlignment < fileAlignment ||
      sectionAlignment & (sectionAlignment - 1) != 0 ||
      fileAlignment & (fileAlignment - 1) != 0 ||
      headersSize < sectionOffset + count * 40 ||
      imageSize < headersSize) {
    reader.fail('Invalid PE image layout');
  }
  reader.bounds(0, headersSize, 'PE headers');
  reader.bounds(sectionOffset, count * 40, 'PE sections');
  final sections = <_MappedRegion>[];
  for (var i = 0; i < count; i++) {
    final section = reader.read(sectionOffset + i * 40, 40);
    final memorySize = _u32(section, 8);
    final address = _u32(section, 12);
    final size = _u32(section, 16);
    final offset = _u32(section, 20);
    reader.bounds(offset, size, 'PE section data');
    if (address % sectionAlignment != 0 ||
        address > imageSize ||
        memorySize > imageSize - address ||
        size > imageSize - address ||
        (size > 0 && (offset < headersSize || offset % fileAlignment != 0))) {
      reader.fail('Invalid PE section layout');
    }
    sections.add(
      _MappedRegion(offset, address, size, _u32(section, 36) & 0x20000000 != 0),
    );
  }
  final exportRva = _u32(optional, directoryStart);
  final exportSize = _u32(optional, directoryStart + 4);
  if (exportRva == 0 || exportSize < 40) {
    reader.fail('PE export directory is missing');
  }
  final exportOffset = _mappedOffset(reader, sections, exportRva, exportSize);
  final directory = reader.read(exportOffset, 40);
  final functionsCount = _u32(directory, 20);
  final namesCount = _u32(directory, 24);
  if (functionsCount == 0 || namesCount > functionsCount) {
    reader.fail('Invalid PE export counts');
  }
  final functions = reader.read(
    _mappedOffset(reader, sections, _u32(directory, 28), functionsCount * 4),
    functionsCount * 4,
  );
  final names = reader.read(
    _mappedOffset(reader, sections, _u32(directory, 32), namesCount * 4),
    namesCount * 4,
  );
  final ordinals = reader.read(
    _mappedOffset(reader, sections, _u32(directory, 36), namesCount * 2),
    namesCount * 2,
  );
  final exportData = reader.read(exportOffset, exportSize);
  final exports = <String>{};
  for (var i = 0; i < namesCount; i++) {
    final ordinal = _u16(ordinals, i * 2);
    if (ordinal >= functionsCount) {
      reader.fail('PE export ordinal is out of bounds');
    }
    final nameRva = _u32(names, i * 4);
    if (nameRva < exportRva || nameRva - exportRva >= exportSize) {
      reader.fail('PE export name is outside the export directory');
    }
    final name = _stringAt(reader, exportData, nameRva - exportRva);
    final address = _u32(functions, ordinal * 4);
    if (address != 0 &&
        (address < exportRva || address - exportRva >= exportSize) &&
        _executableAddress(sections, address)) {
      exports.add(name);
    }
  }
  return exports;
}
