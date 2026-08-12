import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:tailscale/tailscale.dart';

/// An [SSHSocket] that routes through a Tailscale WireGuard tunnel.
///
/// Wraps a [TailscaleConnection] from `package:tailscale` so that dartssh2
/// can communicate over the tailnet without needing a direct TCP connection
/// to the remote host.
class TailscaleSSHSocket extends SSHSocket {
  final TailscaleConnection _connection;
  final _TailscaleSinkAdapter _sinkAdapter;

  TailscaleSSHSocket(this._connection)
    : _sinkAdapter = _TailscaleSinkAdapter(_connection.output);

  @override
  Stream<Uint8List> get stream => _connection.input;

  @override
  StreamSink<List<int>> get sink => _sinkAdapter;

  @override
  Future<void> get done => _connection.done;

  @override
  Future<void> close() => _connection.close();

  @override
  void destroy() => _connection.abort();
}

/// Adapts [TailscaleConnectionOutput] to dart's [StreamSink] interface so
/// dartssh2 can write to the tailnet tunnel.
class _TailscaleSinkAdapter implements StreamSink<List<int>> {
  final TailscaleConnectionOutput _output;

  _TailscaleSinkAdapter(this._output);

  @override
  Future<void> add(List<int> data) => _output.write(data);

  @override
  Future<void> addStream(Stream<List<int>> stream) => _output.writeAll(stream);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    // TailscaleConnectionOutput does not surface errors; ignore.
  }

  @override
  Future<void> close() => _output.close();

  @override
  Future<void> get done => _output.done;
}
