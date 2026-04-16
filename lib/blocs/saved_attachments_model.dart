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

    List<String>? savedAttachmentsPrefs = prefs.getStringList(
      'savedAttachments',
    );

    savedAttachmentsPrefs ??= [];

    list = savedAttachmentsPrefs;

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
    final Iterable<String> savedList = list;
    final List<SavedAttachment> savedAttachmentList = [];

    for (final element in savedList) {
      savedAttachmentList.add(
        SavedAttachment.fromJson(json.decode(element) as Map<String, dynamic>),
      );
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

    if (!list.contains(fileName)) {
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
}
