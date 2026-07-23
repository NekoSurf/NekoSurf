import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_chan/API/save_videos.dart';
import 'package:flutter_chan/Models/saved_attachment.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final savedAttachmentsProvider =
    NotifierProvider<SavedAttachmentsNotifier, SavedAttachmentsState>(
      SavedAttachmentsNotifier.new,
    );

class SavedAttachmentsState {
  const SavedAttachmentsState({this.list = const []});

  final List<String> list;

  List<SavedAttachment> getSavedAttachments() {
    final List<SavedAttachment> result = [];
    for (final element in list) {
      final SavedAttachment? attachment = _decodeSavedAttachment(element);
      if (attachment != null) {
        result.add(attachment);
      }
    }
    return result;
  }

  SavedAttachmentsState copyWith({List<String>? list}) {
    return SavedAttachmentsState(list: list ?? this.list);
  }

  static SavedAttachment? _decodeSavedAttachment(String raw) {
    final String value = raw.trim();
    if (value.isEmpty) {
      return null;
    }
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

  static SavedAttachment _legacyAttachmentFromFileName(String fileName) {
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
}

class SavedAttachmentsNotifier extends Notifier<SavedAttachmentsState> {
  @override
  SavedAttachmentsState build() {
    _loadPreferences();
    return const SavedAttachmentsState();
  }

  Future<void> _loadPreferences() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> raw =
        prefs.getStringList('savedAttachments') ?? [];
    final List<String> normalized = _normalizeEntries(raw);
    if (!_listsEqual(raw, normalized)) {
      await prefs.setStringList('savedAttachments', normalized);
    }
    state = state.copyWith(list: normalized);
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

    final bool alreadySaved = state.getSavedAttachments().any(
      (a) => a.fileName == fileName,
    );

    if (alreadySaved) {
      return;
    }

    final SavedAttachment? savedAttachment = await saveAttachment(
      'https://i.4cdn.org/$board/$fileName',
      'https://i.4cdn.org/$board/${nameWithoutExtension}s.jpg',
      fileName,
      context,
    );

    if (savedAttachment != null) {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final updated = List<String>.from(state.list)
        ..add(json.encode(savedAttachment));
      prefs.setStringList('savedAttachments', updated);
      state = state.copyWith(list: updated);
    }
  }

  Future<void> removeSavedAttachments(
    String path,
    BuildContext context,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<SavedAttachment> savedAttachmentList = state.getSavedAttachments();
    final List<String> newList = [];
    final String pathBaseName = path.split('.').first;

    for (final element in savedAttachmentList) {
      final String elementBaseName = element.fileName!.split('.').first;
      if (elementBaseName != pathBaseName) {
        newList.add(json.encode(element));
      }
    }

    prefs.setStringList('savedAttachments', newList);
    state = state.copyWith(list: newList);

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
      // ignore
    }
  }

  Future<void> clearSavedAttachments(BuildContext context) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setStringList('savedAttachments', []);
    state = const SavedAttachmentsState();

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
      // ignore
    }
  }

  Future<void> setList(List<SavedAttachment> savedAttachments) async {
    final List<String> newList =
        savedAttachments.map((e) => json.encode(e)).toList();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setStringList('savedAttachments', newList);
    state = state.copyWith(list: newList);
  }

  List<String> _normalizeEntries(List<String> entries) {
    final List<String> normalized = [];
    for (final entry in entries) {
      final SavedAttachment? attachment =
          SavedAttachmentsState._decodeSavedAttachment(entry);
      if (attachment != null) {
        normalized.add(json.encode(attachment));
      }
    }
    return normalized;
  }

  bool _listsEqual(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (int i = 0; i < first.length; i++) {
      if (first[i] != second[i]) return false;
    }
    return true;
  }
}
