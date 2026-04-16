import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_chan/API/save_videos.dart';
import 'package:flutter_chan/Models/saved_attachment.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SavedAttachmentsProvider with ChangeNotifier {
  SavedAttachmentsProvider(this.list) {
    loadPreferences();
  }

  List<String> list = [];

  bool playing = true;

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
  ) async {
    final String nameWithoutExtension = fileName.substring(
      0,
      fileName.lastIndexOf('.'),
    );

    if (!_containsFileName(fileName)) {
      final SavedAttachment? savedAttachment = await saveAttachment(
        'https://i.4cdn.org/$board/$fileName',
        'https://i.4cdn.org/$board/${nameWithoutExtension}s.jpg',
        fileName,
        context,
        this,
      );

      if (savedAttachment != null) {
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

    final String pathBaseName = path.split('.').first;

    for (final element in savedAttachmentList) {
      final String elementBaseName = element.fileName!.split('.').first;

      if (elementBaseName == pathBaseName) {
        newList.remove(element);
      } else {
        list.add(json.encode(element));
      }
    }

    prefs.setStringList('savedAttachments', list);

    Directory directory = Directory('');

    try {
      try {
        directory = await requestDirectory(directory, context);
      } catch (e) {
        return;
      }

      directory = Directory('${directory.path}/savedAttachments');

      final List<FileSystemEntity> entities = await directory.list().toList();
      for (final entity in entities) {
        if (entity.path.contains(getNameWithoutExtension(path))) {
          await entity.delete();
        }
      }
    } catch (e) {
      print(e);
    }

    notifyListeners();
  }

  Future<void> clearSavedAttachments(BuildContext context) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    list = [];

    prefs.setStringList('savedAttachments', list);

    notifyListeners();

    Directory directory = Directory('');

    try {
      try {
        directory = await requestDirectory(directory, context);
      } catch (e) {
        return;
      }

      directory = Directory('${directory.path}/savedAttachments');

      final List<FileSystemEntity> entities = await directory.list().toList();
      for (final entity in entities) {
        if (entity is File) {
          await entity.delete();
        }
      }
    } catch (e) {
      print(e);
    }
  }

  void pauseVideo() {
    playing = false;
    notifyListeners();
  }

  void startVideo() {
    playing = true;
    notifyListeners();
  }

  bool getPlaying() {
    return playing;
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

  bool _containsFileName(String fileName) {
    for (final attachment in getSavedAttachments()) {
      if (attachment.fileName == fileName) {
        return true;
      }
    }

    return false;
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
