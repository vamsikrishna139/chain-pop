/// Difficulty modes for level generation.
enum DifficultyMode {
  /// Easy: grids 4×4–6×6, 4–12 nodes, 25% density cap, 2–4 removal waves.
  easy,

  /// Medium: 6×6–10×10, 10–30 nodes, 45% density, 2–6 removal waves.
  medium,

  /// Hard: 6×6–16×16 (ramps with level id), 5–60 nodes, 40% density, 5–10 waves.
  /// Density is slightly below Medium so backward generation keeps succeeding.
  hard,
}
