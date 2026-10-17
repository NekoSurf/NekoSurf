import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_chan/API/save_videos.dart';
import 'package:flutter_chan/Models/saved_attachment.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SavedFilter { all, images, videos }

class SavedAttachmentsProvider with ChangeNotifier {
  SavedAttachmentsProvider(this.list) {
    loadPreferences();
  }

  List<String> list = [];

  bool playing = true;

  bool selecting = false;
  final Set<String> selected = {};

  SavedFilter filter = SavedFilter.all;
  bool newestFirst = true;

  void setFilter(SavedFilter value) {
    filter = value;
    notifyListeners();
  }

  void setNewestFirst(bool value) {
    newestFirst = value;
    notifyListeners();
  }

  List<SavedAttachment> visibleAttachments() {
    final List<SavedAttachment> items = getSavedAttachments().where((a) {
      final bool isVideo = a.savedAttachmentType == SavedAttachmentType.Video;
      if (filter == SavedFilter.images && isVideo) {
        return false;
      }
      if (filter == SavedFilter.videos && !isVideo) {
        return false;
      }
      return true;
    }).toList();
    return newestFirst ? items.reversed.toList() : items;
  }

  Future<void> removeSelected(BuildContext context) async {
    final List<SavedAttachment> targets = getSavedAttachments()
        .where((a) => selected.contains(a.fileName?.split('/').last ?? ''))
        .toList();
    for (final a in targets) {
      await removeSavedAttachments(attachmentId(a), context);
    }
    setSelecting(false);
  }

  void setSelecting(bool value) {
    selecting = value;
    selected.clear();
    notifyListeners();
  }

  void selectAll() {
    selected
      ..clear()
      ..addAll(
        visibleAttachments().map((a) => a.fileName?.split('/').last ?? ''),
      );
    notifyListeners();
  }

  void deselectAll() {
    selected.clear();
    notifyListeners();
  }

  void toggleSelected(String fileName) {
    if (!selected.remove(fileName)) {
      selected.add(fileName);
    }
    notifyListeners();
  }

  Future<void> loadPreferences() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final List<String> savedAttachmentsPrefs =
        prefs.getStringList('savedAttachments') ?? [];

    list = _normalizeSavedEntries(savedAttachmentsPrefs);

    if (!_listsEqual(savedAttachmentsPrefs, list)) {
      await prefs.setStringList('savedAttachments', list);
    }

    notifyListeners();
  }

  Future<void> setList(List<SavedAttachment> savedAttachments) async {
    list = [];

    for (final element in savedAttachments) {
      list.add(json.encode(element));
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();

    prefs.setStringList('savedAttachments', list);

    notifyListeners();
  }

  List<SavedAttachment> getSavedAttachments() {
    final List<SavedAttachment> savedAttachmentList = [];

    for (final element in list) {
      final SavedAttachment? attachment = _decodeSavedAttachment(element);

      if (attachment != null) {
        savedAttachmentList.add(attachment);
      }
    }

    return savedAttachmentList;
  }

  Future<void> addSavedAttachments(
    BuildContext context,
    String board,
    String fileName,
    String downloadName,
  ) async {
    final String nameWithoutExtension = downloadName.substring(
      0,
      downloadName.lastIndexOf('.'),
    );

    if (!_containsId(nameWithoutExtension)) {
      final SavedAttachment? savedAttachment = await saveAttachment(
        'https://i.4cdn.org/$board/$downloadName',
        'https://i.4cdn.org/$board/${nameWithoutExtension}s.jpg',
        downloadName,
        fileName,
        context,
        this,
      );

      if (savedAttachment != null) {
        savedAttachment.originalName = fileName;
        final SharedPreferences prefs = await SharedPreferences.getInstance();

        list.add(json.encode(savedAttachment));

        prefs.setStringList('savedAttachments', list);

        notifyListeners();
      }
    } else {
      print('Already saved');
    }
  }

  Future<void> removeSavedAttachments(String path, BuildContext context) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final List<SavedAttachment> savedAttachmentList = getSavedAttachments();

    final List<SavedAttachment> newList = List<SavedAttachment>.from(
      savedAttachmentList,
    );

    list = [];

    final String pathBaseName = getNameWithoutExtension(path);
    final List<SavedAttachment> removed = [];

    for (final element in savedAttachmentList) {
      final String elementBaseName = attachmentId(element);

      if (elementBaseName == pathBaseName) {
        newList.remove(element);
        removed.add(element);
      } else {
        list.add(json.encode(element));
      }
    }

    prefs.setStringList('savedAttachments', list);

    try {
      Directory directory;
      try {
        directory = await requestDirectory(Directory(''), context);
      } catch (e) {
        return;
      }

      for (final attachment in removed) {
        await _deleteFiles(directory.path, attachment);
      }
    } catch (e) {
      print(e);
    }

    notifyListeners();
  }

  Future<void> clearSavedAttachments(BuildContext context) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final List<SavedAttachment> all = getSavedAttachments();
    list = [];

    prefs.setStringList('savedAttachments', list);

    notifyListeners();

    try {
      Directory directory;
      try {
        directory = await requestDirectory(Directory(''), context);
      } catch (e) {
        return;
      }

      for (final attachment in all) {
        await _deleteFiles(directory.path, attachment);
      }
    } catch (e) {
      print(e);
    }
  }

  Future<void> _deleteFiles(String base, SavedAttachment attachment) async {
    final String media = savedMediaPath(base, attachment.fileName!);
    final String thumb = savedThumbnailPath(base, attachment);
    for (final p in {media, thumb}) {
      final File file = File(p);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  /// Moves thumbnails (and, on iOS, media) out of the old `savedAttachments/`
  /// layout, and drops entries whose media file was deleted outside the app.
  Future<void> reconcileWithDisk(String base) async {
    await _migrateLegacyLayout(base);
    await _renameToOriginalNames(base);

    final List<SavedAttachment> kept = [];
    bool changed = false;

    for (final attachment in getSavedAttachments()) {
      if (await File(savedMediaPath(base, attachment.fileName!)).exists()) {
        kept.add(attachment);
        continue;
      }
      changed = true;
      final File thumb = File(savedThumbnailPath(base, attachment));
      if (attachment.thumbnail != attachment.fileName && await thumb.exists()) {
        await thumb.delete();
      }
    }

    if (changed) {
      await setList(kept);
    }
  }

  Future<void> _migrateLegacyLayout(String base) async {
    final Directory legacy = Directory('$base/savedAttachments');
    if (!await legacy.exists()) {
      return;
    }

    Future<void> move(File source, String target) async {
      if (!await source.exists() || await File(target).exists()) {
        return;
      }
      try {
        await source.rename(target);
      } catch (_) {
        await source.copy(target);
        await source.delete();
      }
    }

    for (final attachment in getSavedAttachments()) {
      final String name = attachment.fileName!;
      await move(File('${legacy.path}/$name'), savedMediaPath(base, name));
      if (attachment.thumbnail != null && attachment.thumbnail != name) {
        await move(
          File('${legacy.path}/${attachment.thumbnail}'),
          savedThumbnailPath(base, attachment),
        );
      }
    }

    if (await legacy.list().isEmpty) {
      await legacy.delete();
    }
  }

  List<String> _normalizeSavedEntries(List<String> entries) {
    final List<String> normalized = [];

    for (final entry in entries) {
      final SavedAttachment? attachment = _decodeSavedAttachment(entry);

      if (attachment != null) {
        normalized.add(json.encode(attachment));
      }
    }

    return normalized;
  }

  SavedAttachment? _decodeSavedAttachment(String raw) {
    final String value = raw.trim();

    if (value.isEmpty) {
      return null;
    }

    // Older versions stored just the filename. Build a minimal valid object.
    if (!value.startsWith('{')) {
      return _legacyAttachmentFromFileName(value);
    }

    try {
      final dynamic decoded = json.decode(value);

      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      return SavedAttachment.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  SavedAttachment _legacyAttachmentFromFileName(String fileName) {
    final String lower = fileName.toLowerCase();
    final bool isVideo =
        lower.endsWith('.mp4') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.gif');
    final String baseName = getNameWithoutExtension(fileName);

    return SavedAttachment(
      savedAttachmentType: isVideo
          ? SavedAttachmentType.Video
          : SavedAttachmentType.Image,
      fileName: fileName,
      thumbnail: isVideo ? '$baseName.jpg' : fileName,
    );
  }

  /// Stable upload id; older entries were stored under the id as file name.
  String attachmentId(SavedAttachment a) =>
      a.id ?? getNameWithoutExtension(a.fileName!.split('/').last);

  bool _containsId(String id) {
    return getSavedAttachments().any((a) => attachmentId(a) == id);
  }

  /// Gives legacy id-named files the uploader's filename.
  Future<void> _renameToOriginalNames(String base) async {
    final List<SavedAttachment> all = getSavedAttachments();
    bool changed = false;

    for (final attachment in all) {
      final String? original = attachment.originalName;
      final String name = attachment.fileName!;
      if (attachment.id != null || original == null || original.isEmpty) {
        continue;
      }
      attachment.id = getNameWithoutExtension(name);
      changed = true;

      final File file = File(savedMediaPath(base, name));
      if (!await file.exists()) {
        continue;
      }
      final String ext = name.contains('.')
          ? '.${name.split('.').last.toLowerCase()}'
          : '';
      final String? target = await uniqueSavedFileName(
        savedMediaDirPath(base),
        original,
        ext,
      );
      if (target == null || target == name) {
        continue;
      }
      try {
        await file.rename(savedMediaPath(base, target));
      } catch (_) {
        continue;
      }
      if (attachment.thumbnail == name) {
        attachment.thumbnail = target;
      }
      attachment.fileName = target;
    }

    if (changed) {
      await setList(all);
    }
  }

  bool _listsEqual(List<String> first, List<String> second) {
    if (first.length != second.length) {
      return false;
    }

    for (int i = 0; i < first.length; i++) {
      if (first[i] != second[i]) {
        return false;
      }
    }

    return true;
  }
}
