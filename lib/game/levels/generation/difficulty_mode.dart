/// Difficulty modes for level generation
enum DifficultyMode {
  /// Easy mode: smaller grids (4x4-6x6), fewer nodes (4-12), lower density (25%)
  easy,
  
  /// Medium mode: mid-size grids (6x6-10x10), moderate nodes (10-30), medium density (45%)
  medium,
  
  /// Hard mode: larger grids (10x10-20x20), many nodes (25-100), high density (65%)
  hard,
}
