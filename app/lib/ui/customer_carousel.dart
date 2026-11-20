import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import 'format.dart';

/// Cyzen-style bottom card carousel shown while a customer is selected.
///
/// Cards follow the order of [AppState.visible] — the same filtered list
/// both map implementations use for their pins. Swiping to another card
/// selects that customer through [onSelect]; MapPage's existing selection
/// listener then centres the camera on its pin. When the selected customer
/// is filtered out of the visible list it is prepended so the carousel
/// always contains the current selection.
class CustomerCardCarousel extends StatefulWidget {
  const CustomerCardCarousel({
    super.key,
    required this.state,
    required this.onSelect,
    required this.onCall,
    required this.onNav,
    required this.onDetails,
    required this.onClose,
  });

  final AppState state;
  final ValueChanged<Customer> onSelect;
  final ValueChanged<Customer> onCall;
  final ValueChanged<Customer> onNav;
  final VoidCallback onDetails;
  final VoidCallback onClose;

  @override
  State<CustomerCardCarousel> createState() => _CustomerCardCarouselState();
}

class _CustomerCardCarouselState extends State<CustomerCardCarousel> {
  late final PageController _controller;
  String? _shownId;

  List<Customer> get _customers {
    final selected = widget.state.selected;
    final visible = widget.state.visible;
    if (selected == null) return visible;
    if (visible.any((customer) => customer.id == selected.id)) return visible;
    return [selected, ...visible];
  }

  int get _selectedIndex {
    final selected = widget.state.selected;
    if (selected == null) return 0;
    final index = _customers.indexWhere((customer) => customer.id == selected.id);
    return index < 0 ? 0 : index;
  }

  @override
  void initState() {
    super.initState();
    _shownId = widget.state.selected?.id;
    _controller = PageController(viewportFraction: 0.92, initialPage: _selectedIndex);
  }

  @override
  void didUpdateWidget(covariant CustomerCardCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = widget.state.selected;
    if (selected == null || selected.id == _shownId) return;
    // Selection changed from outside the carousel (pin tap, recall button):
    // move the pager to the newly selected customer's card.
    _shownId = selected.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final index = _selectedIndex;
      if ((_controller.page?.round() ?? index) != index) {
        _controller.jumpToPage(index);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customers = _customers;
    if (widget.state.selected == null || customers.isEmpty) {
      return const SizedBox.shrink();
    }
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity < -300) {
              widget.onDetails();
            } else if (velocity > 300) {
              widget.onClose();
            }
          },
          child: SizedBox(
            height: 48,
            child: Stack(
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(color: const Color(0xFFDADCE0), borderRadius: BorderRadius.circular(3)),
                  ),
                ),
                Positioned(
                  right: 4,
                  top: 0,
                  bottom: 0,
                  child: IconButton(
                    tooltip: '閉じる',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close),
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _controller,
            itemCount: customers.length,
            onPageChanged: (index) {
              final customer = customers[index];
              _shownId = customer.id;
              if (customer.id != widget.state.selected?.id) {
                widget.onSelect(customer);
              }
            },
            itemBuilder: (context, index) => _card(customers[index]),
          ),
        ),
        SizedBox(height: bottomInset),
      ],
    );
  }

  Widget _card(Customer customer) {
    final status = widget.state.statusOf(customer.statusId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(5, 2, 5, 8),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFDADCE0)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onDetails,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.circle, size: 14, color: colorFromHex(status?.colorHex ?? '#1A73E8')),
                    const SizedBox(width: 6),
                    Text(status?.label ?? '', style: const TextStyle(fontSize: 14, color: Color(0xFF5F6368))),
                    if (customer.pendingSync) ...[
                      const SizedBox(width: 8),
                      const Text('同期待ち', style: TextStyle(fontSize: 13, color: Color(0xFF8A5A00))),
                    ],
                    if (customer.sharedWithMe) ...[
                      const SizedBox(width: 8),
                      const Text('共有', style: TextStyle(fontSize: 13, color: Color(0xFF1A73E8))),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  customer.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  customer.address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, color: Color(0xFF3C4043)),
                ),
                const Spacer(),
                Row(
                  children: [
                    const Text('単価（1回）', style: TextStyle(fontSize: 13, color: Color(0xFF80868B))),
                    const SizedBox(width: 10),
                    Text(formatYen(customer.unitPrice), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: SizedBox(
                        height: 56,
                        child: FilledButton.icon(
                          onPressed: () => widget.onNav(customer),
                          icon: const Icon(Icons.directions, size: 20),
                          label: const Text('ルート案内', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                    ),
                    if (customer.phone.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: SizedBox(
                          height: 56,
                          child: OutlinedButton.icon(
                            onPressed: () => widget.onCall(customer),
                            icon: const Icon(Icons.call, size: 20),
                            label: const Text('電話', style: TextStyle(fontSize: 16)),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: SizedBox(
                        height: 56,
                        child: OutlinedButton.icon(
                          onPressed: widget.onDetails,
                          icon: const Icon(Icons.edit_note, size: 20),
                          label: const Text('詳細', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
