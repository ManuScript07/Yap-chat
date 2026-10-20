// Copyright 2019 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';

import 'item_positions_listener.dart';

/// Internal implementation of [ItemPositionsListener].
class ItemPositionsNotifier implements ItemPositionsListener {
  /// Scroll coordinate at which [itemPositions] were measured. A pointer can
  /// move again before the next layout publishes another set of item edges.
  double? measuredPixels;

  @override
  final ValueNotifier<Iterable<ItemPosition>> itemPositions = ValueNotifier([]);
}
