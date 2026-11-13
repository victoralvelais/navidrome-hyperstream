#include <algorithm>
#include <cassert>
#include <iostream>
#include <numeric>
#include <string>
#include <vector>

#include "../apps/client/packages/just_audio_windows/windows/playback_queue.hpp"

int main() {
  using hyperstream::ApplyShuffleOrder;
  const std::vector<std::string> songs{"first occurrence", "second", "repeat occurrence"};
  assert((ApplyShuffleOrder(songs, {1, 2, 0}) ==
          std::vector<std::string>{"second", "repeat occurrence", "first occurrence"}));
  // All small permutations catch reverse/move mappings and off-by-one errors.
  for (int size = 0; size <= 7; ++size) {
    std::vector<int64_t> indices(size);
    std::iota(indices.begin(), indices.end(), 0);
    const auto original = indices;
    do {
      assert(ApplyShuffleOrder(original, indices) == indices);
    } while (std::next_permutation(indices.begin(), indices.end()));
  }
  for (const auto& bad : std::vector<std::vector<int64_t>>{{0}, {0, 0, 2}, {-1, 1, 2}, {0, 1, 3}}) {
    bool rejected = false;
    try { ApplyShuffleOrder(songs, bad); }
    catch (const std::invalid_argument&) { rejected = true; }
    assert(rejected);
  }
  assert(songs[0] == "first occurrence");
  std::cout << "Native queue traversal checks passed\n";
}
