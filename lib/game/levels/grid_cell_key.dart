/// Packed grid coordinate key for hot-path occupancy sets/maps.
///
/// Uses lower 16 bits for `x`, next 16 bits for `y`. Valid while coordinates
/// stay within \[0, 65535\] (far beyond any Chain Pop board).
@pragma('vm:prefer-inline')
int gridCellKey(int x, int y) =>
    (x & 0xffff) | ((y & 0xffff) << 16);
