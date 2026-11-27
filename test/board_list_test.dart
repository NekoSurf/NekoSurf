import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/chan/board.dart';
import 'package:flutter_chan/home/dashboard.dart';
import 'package:flutter_chan/home/dashboard_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("leaves out the board's name and what 4chan calls it", () {
    // As 4chan words them (decoded from HTML).
    const Map<String, String> blurbs = {
      '"/3/ - 3DCG" is 4chan\'s board for 3D modeling and imagery.':
          '3D modeling and imagery.',
      '"/a/ - Anime & Manga" is 4chan\'s imageboard dedicated to the '
              'discussion of Japanese animation and manga.':
          'Japanese animation and manga.',
      '"/adv/ - Advice" is 4chan\'s board for giving and receiving advice. ':
          'Giving and receiving advice.',
      '"/an/ - Animals & Nature" is 4chan\'s imageboard for posting pictures '
              'of animals, pets, and nature.':
          'Animals, pets, and nature.',
      '"/f/ - Flash" is 4chan\'s upload board for sharing Adobe Flash files '
              '(SWFs).':
          'Adobe Flash files (SWFs).',
      '"/his/ - History & Humanities" is 4chan\'s board for discussing and '
              'debating history.':
          'History.',
      '"/p/ - Photography" is 4chan\'s imageboard for sharing and critiquing '
              'photos.':
          'Sharing and critiquing photos.',
      '"/r9k/ - ROBOT9001" is a board for hanging out and posting greentext '
              'stories.':
          'Hanging out and posting greentext stories.',
      '"/xs/ - Extreme Sports" is 4chan\'s imageboard imageboard dedicated to '
              'the discussion of extreme sports.':
          'Extreme sports.',
      // Worded otherwise: what's after the name stays.
      '"/b/ - Random" is the birthplace of Anonymous.':
          'Birthplace of Anonymous.',
      '"/news/ - Current News; is 4chan\'s board for current news. ':
          'Current news.',
    };
    blurbs.forEach((description, blurb) {
      expect(boardBlurb(description), blurb, reason: description);
    });
  });

  test('keeps a description it cannot make out', () {
    expect(boardBlurb(''), '');
    expect(boardBlurb('Just a board.'), 'Just a board.');
  });

  group('the list under Favorites', () {
    final List<Board> boards = [
      Board(board: 'g', title: 'Technology'),
      Board(board: 'a', title: 'Anime & Manga'),
      Board(board: 'c', title: 'Anime/Cute'),
    ];
    List<String> listed(String query, Set<String> favorites) => [
      for (final Board b in listedBoards(
        boards,
        query: query,
        isFavorite: favorites.contains,
      ))
        b.board,
    ];

    test('leaves out the favorites, which have their own list', () {
      expect(listed('', {'a'}), ['c', 'g']);
      expect(listed('', {}), ['a', 'c', 'g']);
    });

    test('finds favorites too when searching', () {
      expect(listed('anime', {'a'}), ['a', 'c']);
      expect(listed('TECH', {'a'}), ['g']);
    });
  });

  test('lists a board under its first letter, or # for a digit', () {
    expect(boardLetter('a'), 'A');
    expect(boardLetter('vrpg'), 'V');
    expect(boardLetter('3'), '#');
    expect(boardLetter('r9k'), 'R');
  });

  testWidgets('a board row is one line, swiped to favorite it', (tester) async {
    int toggled = 0;
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: Center(
            child: DashBoardRow(
              board: 'g',
              title: 'Technology',
              description: 'Computer hardware and software.',
              isFavorite: false,
              nsfw: false,
              onTap: () {},
              onToggleFavorite: () => toggled++,
            ),
          ),
        ),
      ),
    );
    expect(find.text('/g/'), findsOneWidget);
    expect(
      find.text(
        'Technology  Computer hardware and software.',
        findRichText: true,
      ),
      findsOneWidget,
    );
    // No heart till swiped.
    expect(find.text('Favorite'), findsNothing);

    await tester.drag(find.text('/g/'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favorite'));
    await tester.pumpAndSettle();
    expect(toggled, 1);
  });
}
