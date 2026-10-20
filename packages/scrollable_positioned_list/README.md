# Local chat pagination patch

Source: `scrollable_positioned_list` 0.3.8, Google flutter.widgets.
The upstream BSD license is retained in LICENSE. No Pub-cache files are changed.

Changes include optional stable `itemKeyBuilder` identities and
`maintainVisiblePosition` for non-separated lists. The latter rebases the
positioned list before layout instead of calling `jumpTo` or replacing the
scrollable on each page. Flutter retains the drag/ballistic activity. Keyed
registered rows and sliver index callbacks preserve message/reaction state even
when a retained row moves across the center sliver. Key maps contain only the
current bounded page; they do not accumulate the history.

Position snapshots also record their measured scroll offset. Rebasing retains
any additional pointer movement since that measurement, including when a new
page and a drag update arrive before the same frame is laid out.

Canceled long-distance transitions also invalidate deferred animation callbacks
and complete their pending start futures. A stale callback can no longer leave
the sole active list transparent or mutate a later navigation's animation.

ChatPage enables position retention only for its focused history. Explicit reply
navigation and the animated down button continue using the existing controller.
Calls without item keys keep the upstream behavior. Separated lists do not use
this extension. See `test/features/chat/keyed_history_pagination_test.dart` and
`composer_reply_navigation_test.dart` for the regression coverage.
