/// Packed grid coordinate key for hot-path occupancy sets/maps.
///
/// Uses lower 16 bits for `x`, next 16 bits for `y`. Valid while coordinates
/// stay within \[0, 65535\] (far beyond any Chain Pop board).
@pragma('vm:prefer-inline')
int gridCellKey(int x, int y) => (x & 0xffff) | ((y & 0xffff) << 16);

/// `x` of a [gridCellKey]. Never decode keys with `% 1000` / `~/ 1000` — that
/// is the base-1000 scheme this packing replaced, and it silently produced
/// out-of-board portal coordinates (audit P1-6a).
@pragma('vm:prefer-inline')
int gridCellX(int key) => key & 0xffff;

/// `y` of a [gridCellKey].
@pragma('vm:prefer-inline')
int gridCellY(int key) => (key >> 16) & 0xffff;
