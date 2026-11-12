import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../logic/cluster.dart';
import '../logic/price_tiers.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import 'format.dart';
import 'pin_painter.dart';

class SalesGoogleMap extends StatefulWidget {
  const SalesGoogleMap({super.key, required this.state, required this.onLongPress, this.here});

  final AppState state;
  final void Function(double lat, double lng) onLongPress;
  final Position? here;

  @override
  State<SalesGoogleMap> createState() => SalesGoogleMapState();
}

class SalesGoogleMapState extends State<SalesGoogleMap> {
  GoogleMapController? _controller;
  double _zoom = 13;
  final Map<String, BitmapDescriptor> _icons = {};
  BitmapDescriptor? _hereIcon;

  @override
  void initState() {
    super.initState();
    _loadHereIcon();
  }

  Future<void> _loadHereIcon() async {
    final image = await _blueDotImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null || !mounted) return;
    setState(() {
      _hereIcon = BitmapDescriptor.bytes(bytes.buffer.asUint8List(), width: 28, height: 28);
    });
  }

  @override
  Widget build(BuildContext context) {
    final markers = _markers();
    return GoogleMap(
      initialCameraPosition: const CameraPosition(target: LatLng(35.682, 139.772), zoom: 13),
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      markers: markers,
      circles: _hereCircle(),
      onMapCreated: (controller) => _controller = controller,
      onCameraMove: (position) => _zoom = position.zoom,
      onCameraIdle: () => setState(() {}),
      onTap: (_) => widget.state.setSheet(SheetLevel.closed),
      onLongPress: (position) => widget.onLongPress(position.latitude, position.longitude),
    );
  }

  Future<void> moveTo(double lat, double lng) async {
    await _controller?.animateCamera(CameraUpdate.newLatLng(LatLng(lat, lng)));
  }

  Set<Marker> _markers() {
    final located = widget.state.visible.where((customer) => customer.hasLocation).toList();
    final points = [
      for (final customer in located) PinPos(customer.id, _x(customer.lng!), _y(customer.lat!)),
    ];
    final clusters = clusterPins(points, radius: 0.22);
    final byId = {for (final customer in located) customer.id: customer};
    return clusters.map((cluster) {
      if (cluster.isCluster) {
        final lat = _latFromY(cluster.y);
        final lng = _lngFromX(cluster.x);
        return Marker(
          markerId: MarkerId('cluster-${cluster.ids.first}'),
          position: LatLng(lat, lng),
          onTap: () {
            _zoom = (_zoom + 2).clamp(3, 20);
            _controller?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), _zoom));
            setState(() {});
          },
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(title: '${cluster.ids.length}件'),
        );
      }
      final customer = byId[cluster.ids.single]!;
      final status = widget.state.statusOf(customer.statusId);
      final selected = customer.id == widget.state.selectedId;
      final icon = _icons[_key(customer, selected)] ?? BitmapDescriptor.defaultMarkerWithHue(_hue(status?.colorHex));
      _ensureIcon(customer, selected);
      return Marker(
        markerId: MarkerId(customer.id),
        position: LatLng(customer.lat!, customer.lng!),
        icon: icon,
        zIndexInt: 100 - (status?.sortOrder ?? 0),
        onTap: () => widget.state.selectCustomer(customer.id),
        onDragEnd: (position) {
          widget.state.moveSelectedPin(position.latitude, position.longitude);
          widget.state.persistSelectedPin();
        },
        draggable: selected,
      );
    }).toSet()
      ..addAll(_hereMarker())
      ..addAll(_dropMarker());
  }

  Set<Marker> _dropMarker() {
    final drop = widget.state.drop;
    if (drop == null) return const {};
    return {
      Marker(
        markerId: const MarkerId('drop'),
        position: LatLng(drop.lat, drop.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose),
        anchor: const Offset(0.5, 1),
        zIndexInt: 900,
        consumeTapEvents: true,
        infoWindow: const InfoWindow(title: '新規'),
      ),
    };
  }

  Set<Circle> _hereCircle() {
    final here = widget.here;
    if (here == null) return const {};
    final radius = here.accuracy.isFinite && here.accuracy > 0 ? here.accuracy : 30.0;
    return {
      Circle(
        circleId: const CircleId('here'),
        center: LatLng(here.latitude, here.longitude),
        radius: radius,
        fillColor: const Color(0x334285F4),
        strokeColor: const Color(0x664285F4),
        strokeWidth: 1,
        consumeTapEvents: true,
        zIndex: 0,
      ),
    };
  }

  Set<Marker> _hereMarker() {
    final here = widget.here;
    final icon = _hereIcon;
    if (here == null || icon == null) return const {};
    return {
      Marker(
        markerId: const MarkerId('here'),
        position: LatLng(here.latitude, here.longitude),
        icon: icon,
        anchor: const Offset(0.5, 0.5),
        zIndexInt: 1000,
        consumeTapEvents: true,
      ),
    };
  }

  String _key(Customer customer, bool selected) => '${customer.statusId}-${widget.state.tiers.tierOf(customer.unitPrice)}-$selected';

  Future<void> _ensureIcon(Customer customer, bool selected) async {
    final key = _key(customer, selected);
    if (_icons.containsKey(key)) return;
    final status = widget.state.statusOf(customer.statusId);
    final diameter = pinDiameterForTier(widget.state.tiers.tierOf(customer.unitPrice));
    final image = await pinImage(fill: colorFromHex(status?.colorHex ?? '#1A73E8'), shape: status?.shape ?? 'check', diameter: diameter * 2, selected: selected);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null || !mounted) return;
    _icons[key] = BitmapDescriptor.bytes(
      bytes.buffer.asUint8List(),
      width: diameter,
      height: diameter * 1.35,
    );
    if (mounted) setState(() {});
  }

  double _hue(String? hex) {
    return switch (hex?.toUpperCase()) {
      '#F9AB00' => BitmapDescriptor.hueYellow,
      '#12B5CB' => BitmapDescriptor.hueCyan,
      '#5F6368' => BitmapDescriptor.hueRose,
      '#E37400' => BitmapDescriptor.hueOrange,
      '#1E8E3E' => BitmapDescriptor.hueGreen,
      '#D93025' => BitmapDescriptor.hueRed,
      '#9334E6' => BitmapDescriptor.hueViolet,
      _ => BitmapDescriptor.hueAzure,
    };
  }

  double get _scale => math.pow(2, _zoom).toDouble();
  double _x(double lng) => (lng + 180) / 360 * _scale;
  double _y(double lat) {
    final sinLat = math.sin(lat * math.pi / 180).clamp(-0.9999, 0.9999);
    return (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) * _scale;
  }

  double _sinh(double value) => (math.exp(value) - math.exp(-value)) / 2;

  double _lngFromX(double x) => x / _scale * 360 - 180;
  double _latFromY(double y) {
    final n = math.pi - 2 * math.pi * y / _scale;
    return 180 / math.pi * math.atan(_sinh(n));
  }
}

Future<ui.Image> _blueDotImage() {
  const size = 64.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final center = const Offset(size / 2, size / 2);
  canvas.drawCircle(center, 16, Paint()..color = const Color(0x553A7BFF));
  canvas.drawCircle(center, 11, Paint()..color = Colors.white);
  canvas.drawCircle(center, 8, Paint()..color = const Color(0xFF1A73E8));
  return recorder.endRecording().toImage(size.toInt(), size.toInt());
}
