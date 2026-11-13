#pragma once

#include <cstdint>
#include <stdexcept>
#include <vector>

namespace hyperstream {

// just_audio supplies traversal indices, not a series of in-place moves.
// Keep occurrences distinct even when several items refer to the same song.
template <typename Item>
std::vector<Item> ApplyShuffleOrder(const std::vector<Item>& items,
                                    const std::vector<int64_t>& order) {
  if (order.size() != items.size()) {
    throw std::invalid_argument("Invalid shuffle order length");
  }
  std::vector<bool> seen(items.size(), false);
  std::vector<Item> result;
  result.reserve(items.size());
  for (const auto index : order) {
    if (index < 0 || static_cast<uint64_t>(index) >= items.size() ||
        seen[static_cast<size_t>(index)]) {
      throw std::invalid_argument("Invalid shuffle order index");
    }
    seen[static_cast<size_t>(index)] = true;
    result.push_back(items[static_cast<size_t>(index)]);
  }
  return result;
}

}  // namespace hyperstream
