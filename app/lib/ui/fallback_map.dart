import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../logic/cluster.dart';
import '../logic/geo.dart';
import '../logic/price_tiers.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import 'format.dart';
import 'pin_painter.dart';

class FallbackMap extends StatefulWidget {
  const FallbackMap({super.key, required this.state, required this.onLongPress, this.here});

  final AppState state;
  final void Function(double lat, double lng) onLongPress;
  final Position? here;

  @override
  State<FallbackMap> createState() => FallbackMapState();
}

class FallbackMapState extends State<FallbackMap> {
  double centerLat = 35.682;
  double centerLng = 139.772;
  double scale = 14000;

  void zoomIn() => setState(() => scale = (scale * 1.4).clamp(2000, 80000));
  void zoomOut() => setState(() => scale = (scale / 1.4).clamp(2000, 80000));

  void focus(double lat, double lng) => setState(() {
    centerLat = lat;
    centerLng = lng;
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final points = <PinPos>[];
        final byId = <String, Customer>{};
        for (final customer in widget.state.visible) {
          if (!customer.hasLocation) continue;
          final offset = _project(customer.lat!, customer.lng!, size);
          points.add(PinPos(customer.id, offset.dx, offset.dy));
          byId[customer.id] = customer;
        }
        final clusters = clusterPins(points, radius: 46);
        return GestureDetector(
          onScaleUpdate: (details) {
            setState(() {
              centerLng -= details.focalPointDelta.dx / scale;
              centerLat += details.focalPointDelta.dy / scale;
              if (details.scale != 1) scale = (scale * (1 + (details.scale - 1) * 0.15)).clamp(2000, 80000);
            });
          },
          onLongPressStart: (details) {
            final lat = centerLat - (details.localPosition.dy - size.height / 2) / scale;
            final lng = centerLng + (details.localPosition.dx - size.width / 2) / scale;
            widget.onLongPress(lat, lng);
          },
          child: Stack(
            children: [
              CustomPaint(size: size, painter: _StreetPainter()),
              for (final cluster in clusters)
                if (cluster.isCluster)
                  Positioned(
                    left: cluster.x - 24,
                    top: cluster.y - 24,
                    child: GestureDetector(
                      onTap: () => setState(() => scale = (scale * 1.8).clamp(2000, 80000)),
                      child: Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF5F6368), width: 3),
                        ),
                        child: Text('${cluster.ids.length}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  )
                else
                  _pin(byId[cluster.ids.single]!, cluster.x, cluster.y),
              if (widget.here != null) _hereDot(widget.here!, size),
            ],
          ),
        );
      },
    );
  }

  Widget _pin(Customer customer, double x, double y) {
    final status = widget.state.statusOf(customer.statusId);
    final tier = widget.state.tiers.tierOf(customer.unitPrice);
    final diameter = pinDiameterForTier(tier);
    final selected = customer.id == widget.state.selectedId && widget.state.sheet != SheetLevel.closed;
    final height = diameter * 1.35;
    return Positioned(
      left: x - diameter / 2,
      top: y - height,
      child: GestureDetector(
        onTap: () => widget.state.selectCustomer(customer.id),
        onPanUpdate: selected
            ? (details) {
                final lat = customer.lat! - details.delta.dy / scale;
                final lng = customer.lng! + details.delta.dx / scale;
                widget.state.moveSelectedPin(lat, lng);
              }
            : null,
        child: SizedBox(
          width: diameter < 48 ? 48 : diameter,
          height: height + 8,
          child: CustomPaint(
            painter: PinGlyphPainter(
              fill: colorFromHex(status?.colorHex ?? '#1A73E8'),
              shape: status?.shape ?? 'check',
              selected: selected,
            ),
          ),
        ),
      ),
    );
  }

  Widget _hereDot(Position here, Size size) {
    final point = _project(here.latitude, here.longitude, size);
    final accuracy = here.accuracy.isFinite && here.accuracy > 0 ? here.accuracy : 30.0;
    final radius = accuracyRadiusPixels(meters: accuracy, pixelsPerDegree: scale).clamp(12.0, 240.0);
    return Positioned(
      left: point.dx - radius,
      top: point.dy - radius,
      child: GestureDetector(
        onTap: () {},
        child: SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: CustomPaint(painter: _HereDotPainter(radius)),
        ),
      ),
    );
  }

  Offset _project(double lat, double lng, Size size) {
    return Offset((lng - centerLng) * scale + size.width / 2, (centerLat - lat) * scale + size.height / 2);
  }
}

class _HereDotPainter extends CustomPainter {
  const _HereDotPainter(this.radius);
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, radius, Paint()..color = const Color(0x334285F4));
    canvas.drawCircle(center, 9, Paint()..color = Colors.white);
    canvas.drawCircle(center, 6, Paint()..color = const Color(0xFF1A73E8));
  }

  @override
  bool shouldRepaint(covariant _HereDotPainter oldDelegate) => oldDelegate.radius != radius;
}

class _StreetPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFE7E4DA));
    final block = Paint()..color = const Color(0xFFF7F4EC);
    for (var y = -1; y < 8; y++) {
      for (var x = -1; x < 6; x++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x * 120 + 18, y * 150 + 24, 92, 112), const Radius.circular(8)),
          block,
        );
      }
    }
    final road = Paint()
      ..color = Colors.white
      ..strokeWidth = 14;
    for (var y = 0.0; y < size.height + 40; y += 150) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), road);
    }
    for (var x = 0.0; x < size.width + 40; x += 120) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), road);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
