import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../logic/photo_compress.dart';
import '../models/models.dart';
import '../services/image_vault.dart';
import '../state/app_state.dart';

class CustomerPhotoStrip extends StatelessWidget {
  const CustomerPhotoStrip({super.key, required this.state, required this.customer, this.allowEdit = false, this.compact = false});

  final AppState state;
  final Customer customer;
  final bool allowEdit;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact) const Text('写真', style: TextStyle(fontSize: 14, color: Color(0xFF5F6368))),
        if (!compact) const SizedBox(height: 8),
        SizedBox(
          height: compact ? 96 : 112,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final photo in customer.photos)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _Thumb(
                    state: state,
                    photo: photo,
                    size: compact ? 96 : 112,
                    onOpen: () => _open(context, photo),
                    onDelete: allowEdit ? () => _delete(context, photo) : null,
                  ),
                ),
              if (allowEdit && customer.photos.length < 12) ...[
                _AddTile(label: '撮影', icon: Icons.photo_camera, onTap: () => _pick(context, ImageSource.camera)),
                const SizedBox(width: 8),
                _AddTile(label: '写真', icon: Icons.photo_library, onTap: () => _pick(context, ImageSource.gallery)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context, ImageSource source) async {
    final picker = ImagePicker();
    final List<XFile> files;
    if (source == ImageSource.gallery) {
      files = await picker.pickMultiImage(imageQuality: 85);
    } else {
      final shot = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      files = [if (shot != null) shot];
    }
    if (files.isEmpty) return;
    var photos = [...customer.photos];
    for (final file in files) {
      if (photos.length >= 12) break;
      final raw = await file.readAsBytes();
      final jpeg = compressCustomerPhoto(raw);
      final localPath = await ImageVault().save(jpeg);
      photos.add(CustomerPhoto(id: state.newId(), localPath: localPath, pending: !state.repo.sampleMode));
    }
    await state.repo.saveCustomerPhotos(customer.copyWith(photos: photos));
    await state.refresh();
    if (context.mounted) state.showToast('写真を保存しました');
  }

  Future<void> _delete(BuildContext context, CustomerPhoto photo) async {
    final ok = await state.confirm?.call('この写真を削除しますか') ?? false;
    if (!ok) return;
    final photos = customer.photos.where((item) => item.id != photo.id).toList();
    await state.repo.saveCustomerPhotos(customer.copyWith(photos: photos));
    await state.refresh();
  }

  Future<void> _open(BuildContext context, CustomerPhoto photo) async {
    final bytes = await state.repo.loadPhoto(photo);
    if (!context.mounted) return;
    if (bytes == null) {
      state.showToast('写真を表示できませんでした');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
            const SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: _PhotoBack(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoBack extends StatelessWidget {
  const _PhotoBack();

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => Navigator.pop(context),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black54,
        minimumSize: const Size(48, 56),
      ),
      icon: const Icon(Icons.arrow_back, size: 26),
      label: const Text('閉じる', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.state, required this.photo, required this.onOpen, this.onDelete, this.size = 112});

  final AppState state;
  final CustomerPhoto photo;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: Material(
              color: const Color(0xFFE7E4DA),
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onOpen,
                child: FutureBuilder<Uint8List?>(
                  future: state.repo.loadPhoto(photo),
                  builder: (context, snapshot) {
                    final bytes = snapshot.data;
                    if (bytes == null) {
                      return const Center(child: Icon(Icons.image, size: 32));
                    }
                    return Image.memory(bytes, fit: BoxFit.cover, width: size, height: size);
                  },
                ),
              ),
            ),
          ),
          if (onDelete != null)
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                tooltip: '削除',
                onPressed: onDelete,
                icon: const Icon(Icons.close, color: Colors.white),
                style: IconButton.styleFrom(backgroundColor: const Color(0xCC202124), minimumSize: const Size(40, 40)),
              ),
            ),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 112,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFDADCE0)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 28),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
