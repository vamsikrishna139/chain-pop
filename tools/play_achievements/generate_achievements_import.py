#!/usr/bin/env python3
"""Build the Play Console bulk-import ZIP for the 48-entry achievement catalog.

Mirrors `lib/services/achievements/achievement_catalog.dart`. The catalog is
frozen (exactly 2,000 points across 48 entries), so it is transcribed here
rather than parsed; ASSERTIONS below fail loudly if the two ever diverge.

Output: out/ChainPop_Achievements_Import.zip containing
  * AchievementsMetadata.csv   (no header row, 7 columns, 48 rows)
  * AchievementsIconsMappings.csv (no header row, 2 columns, 48 rows)
  * 48 x 512x512 placeholder PNG icons

AchievementsLocalizations.csv is deliberately omitted: Play Console rejects the
default locale in that file, and the game ships English-only. The Name and
Description columns of AchievementsMetadata.csv are the default-locale text.

Rules enforced (developer.android.com/games/pgs/integrate-achievements):
  - CSVs must NOT have a header row.
  - Name/Description must not contain commas; Name unique; <=100 / <=500 chars.
  - Points: multiple of 5, 5..200.
  - Steps Needed: integer <= 10000, required iff Incremental value is True,
    blank otherwise.
  - Initial State: Hidden or Revealed.
  - ZIP: no subdirectories, unique filenames, <=403 files, each <1MB, <800MB.
"""

from __future__ import annotations

import os
import struct
import zipfile
import zlib

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
ICON_DIR = os.path.join(OUT_DIR, "icons")
ZIP_NAME = "ChainPop_Achievements_Import.zip"

# (id, name, description, points, incremental, steps_needed, hidden, track)
# `steps` is the value reported to Play Games (already divided by `scale` for
# the two volume tiers that exceed Google's 10,000-step ceiling).
CATALOG = [
    # A - First hour
    ("cold_start", "Cold Start", "Clear level 1.", 5, False, None, False, "firstHour"),
    ("finding_footing", "Finding Footing", "Reach level 10.", 10, True, 10, False, "firstHour"),
    ("hundred_down", "Hundred Down", "Clear 100 nodes.", 15, True, 100, False, "firstHour"),
    ("first_guardian", "First Guardian", "Clear level 25 and defeat your first Guardian.", 15, False, None, False, "firstHour"),
    # B - Depth
    ("journey_begun", "Journey Begun", "Reach level 50 on any difficulty.", 20, True, 50, False, "depth"),
    ("century", "Century", "Reach level 100 on any difficulty.", 25, True, 100, False, "depth"),
    ("deep_run", "Deep Run", "Reach level 250 on any difficulty.", 35, True, 250, False, "depth"),
    ("halfway_home", "Halfway Home", "Reach level 500 on any difficulty.", 50, True, 500, False, "depth"),
    ("final_approach", "Final Approach", "Reach level 750 on any difficulty.", 55, True, 750, False, "depth"),
    ("guardian_40", "Guardian 40", "Clear level 1000 - the last of the authored worlds.", 120, True, 1000, False, "depth"),
    # C - All three tracks
    ("three_fronts", "Three Fronts", "Reach level 50 on Easy Medium and Hard.", 40, True, 3, False, "allTracks"),
    ("triple_threat", "Triple Threat", "Reach level 200 on Easy Medium and Hard.", 70, True, 3, False, "allTracks"),
    # D - Stars
    ("rising_star", "Rising Star", "Earn 100 stars across all difficulties.", 20, True, 100, False, "stars"),
    ("star_collector", "Star Collector", "Earn 500 stars across all difficulties.", 35, True, 500, False, "stars"),
    ("constellation", "Constellation", "Earn 1500 stars across all difficulties.", 60, True, 1500, False, "stars"),
    ("galaxy", "Galaxy", "Earn 3000 stars across all difficulties.", 90, True, 3000, False, "stars"),
    # E - Volume
    ("node_runner", "Node Runner", "Clear 1000 nodes.", 15, True, 1000, False, "volume"),
    ("node_knight", "Node Knight", "Clear 10000 nodes.", 25, True, 10000, False, "volume"),
    ("node_lord", "Node Lord", "Clear 50000 nodes.", 40, True, 5000, False, "volume"),
    ("node_legend", "Node Legend", "Clear 150000 nodes.", 60, True, 10000, False, "volume"),
    # F - Mechanics
    ("core_collector", "Core Collector", "Extract 100 cores.", 25, True, 100, False, "mechanics"),
    ("locksmith", "Locksmith", "Open 50 locked nodes.", 25, True, 50, False, "mechanics"),
    ("relay_runner", "Relay Runner", "Clear 50 relays.", 30, True, 50, False, "mechanics"),
    ("phase_shift", "Phase Shift", "Clear 50 phase gates.", 40, True, 50, False, "mechanics"),
    ("portal_hopper", "Portal Hopper", "Traverse 50 portal pairs.", 45, True, 50, False, "mechanics"),
    # G - Guardians
    ("guardian_hunter", "Guardian Hunter", "Clear 10 Guardian levels.", 30, True, 10, False, "guardians"),
    ("guardian_perfect", "Guardian Perfect", "Earn 3 stars on a Guardian level.", 35, False, None, False, "guardians"),
    ("sector_clean", "Sector Clean", "Earn 3 stars on all five Guardians in a single sector.", 55, True, 5, False, "guardians"),
    # H - Directives
    ("swift_solver", "Swift Solver", "Earn 3 stars on a level with the SWIFT directive.", 15, False, None, False, "directives"),
    ("cascade_creator", "Cascade Creator", "Earn 3 stars on a level with the CASCADE directive.", 25, False, None, False, "directives"),
    ("unaided_mind", "Unaided Mind", "Earn 3 stars on a level with the UNAIDED directive.", 25, False, None, False, "directives"),
    ("absolute_integrity", "Absolute Integrity", "Earn 3 stars on a level with the INTEGRITY directive.", 40, False, None, False, "directives"),
    ("flawless_execution", "Flawless Execution", "Earn 3 stars on a level with the FLAWLESS directive.", 55, False, None, False, "directives"),
    ("full_directive", "Full Directive", "Earn 3 stars on a level of every directive.", 70, True, 5, False, "directives"),
    # I - Skill
    ("chain_reaction", "Chain Reaction", "Reach a x5 extraction combo.", 25, False, None, True, "skill"),
    ("untouchable", "Untouchable", "Clear a Hard level at 100% network integrity.", 40, False, None, False, "skill"),
    ("perfect_ten", "Perfect Ten", "Clear 10 levels in a row without a jam.", 55, True, 10, False, "skill"),
    ("master_planner", "Master Planner", "Clear a Hard level with no undo no hint and no jam.", 65, False, None, False, "skill"),
    # J - Daily Challenge
    ("daily_dabbler", "Daily Dabbler", "Complete your first Daily Challenge.", 15, False, None, False, "daily"),
    ("daily_regular", "Daily Regular", "Complete 10 Daily Challenges.", 30, True, 10, False, "daily"),
    ("daily_devotee", "Daily Devotee", "Complete 50 Daily Challenges.", 55, True, 50, False, "daily"),
    ("daily_archivist", "Daily Archivist", "Complete 10 Daily Challenges from past dates.", 45, True, 10, False, "daily"),
    ("calendar_closer", "Calendar Closer", "Complete every day in a single calendar month.", 80, False, None, False, "daily"),
    # K - Streaks
    ("back_again", "Back Again", "Complete a level on 3 days in a row.", 20, True, 3, False, "streaks"),
    ("weekly_warrior", "Weekly Warrior", "Complete a level on 7 days in a row.", 35, True, 7, False, "streaks"),
    ("dedicated", "Dedicated", "Complete a level on 30 days in a row.", 70, True, 30, False, "streaks"),
    ("unbreakable", "Unbreakable", "Complete a level on 100 days in a row.", 100, True, 100, False, "streaks"),
    # L - Exploration
    ("full_spectrum", "Full Spectrum", "Clear a board from all four silhouette families.", 45, True, 4, False, "exploration"),
]

# Placeholder icon tint per track, so the 48 dummies are at least distinguishable
# in the Play Console list. Replace these PNGs with real art before publishing.
TRACK_COLORS = {
    "firstHour": (0x2E, 0x7D, 0xFF),
    "depth": (0x18, 0x9A, 0xB4),
    "allTracks": (0x7C, 0x4D, 0xFF),
    "stars": (0xF5, 0xA6, 0x23),
    "volume": (0x2F, 0xB0, 0x6C),
    "mechanics": (0xE0, 0x5A, 0x3C),
    "guardians": (0xC0, 0x39, 0x8B),
    "directives": (0x5D, 0x6B, 0x82),
    "skill": (0xD8, 0x3A, 0x3A),
    "daily": (0x1F, 0x8A, 0x4C),
    "streaks": (0xB4, 0x7A, 0x1C),
    "exploration": (0x3B, 0x51, 0xC7),
}

ICON_SIZE = 512


# ---------------------------------------------------------------- validation

def validate() -> None:
    assert len(CATALOG) == 48, f"expected 48 achievements, got {len(CATALOG)}"
    total = sum(row[3] for row in CATALOG)
    assert total == 2000, f"point budget must be exactly 2000, got {total}"

    seen_names: set[str] = set()
    seen_ids: set[str] = set()
    for _id, name, desc, points, incremental, steps, _hidden, track in CATALOG:
        assert _id not in seen_ids, f"duplicate id {_id}"
        seen_ids.add(_id)
        assert name not in seen_names, f"duplicate name {name}"
        seen_names.add(name)

        assert "," not in name, f"comma in name: {name}"
        assert "," not in desc, f"comma in description: {desc}"
        assert name.isascii() and desc.isascii(), f"non-ascii text: {name}"
        assert 0 < len(name) <= 100, f"name length: {name}"
        assert len(desc) <= 500, f"description too long: {name}"

        assert points % 5 == 0 and 5 <= points <= 200, f"bad points: {name} {points}"

        if incremental:
            assert steps is not None, f"incremental without steps: {name}"
            assert 2 <= steps <= 10000, f"steps out of range: {name} {steps}"
        else:
            assert steps is None, f"standard with steps: {name}"

        assert track in TRACK_COLORS, f"unknown track: {track}"


# ---------------------------------------------------------------------- icons

def _png(width: int, height: int, rgb_rows: list[bytearray]) -> bytes:
    """Minimal 8-bit RGB PNG encoder (no third-party deps)."""

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    raw = bytearray()
    for row in rgb_rows:
        raw.append(0)  # filter type 0 (None)
        raw += row

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def make_icon(path: str, color: tuple[int, int, int]) -> None:
    """Solid tinted square with a lighter centred disc - a legible placeholder.

    Keeps the mark well inside the frame: Play Games masks icon corners in the
    unlock toast, so nothing meaningful should sit near the edges.
    """
    r, g, b = color
    light = (min(r + 70, 255), min(g + 70, 255), min(b + 70, 255))
    cx = cy = ICON_SIZE / 2.0
    radius = ICON_SIZE * 0.30
    radius_sq = radius * radius

    rows: list[bytearray] = []
    for y in range(ICON_SIZE):
        row = bytearray()
        dy = y + 0.5 - cy
        dy_sq = dy * dy
        for x in range(ICON_SIZE):
            dx = x + 0.5 - cx
            px = light if dx * dx + dy_sq <= radius_sq else (r, g, b)
            row += bytes(px)
        rows.append(row)

    with open(path, "wb") as fh:
        fh.write(_png(ICON_SIZE, ICON_SIZE, rows))


# ----------------------------------------------------------------------- csv

def build_metadata_csv() -> str:
    lines = []
    for order, (_id, name, desc, points, incremental, steps, hidden, _track) in enumerate(
        CATALOG, start=1
    ):
        lines.append(
            ",".join(
                [
                    name,
                    desc,
                    "True" if incremental else "False",
                    str(steps) if incremental else "",
                    "Hidden" if hidden else "Revealed",
                    str(points),
                    str(order),
                ]
            )
        )
    return "\n".join(lines) + "\n"


def build_icons_csv() -> str:
    lines = [f"{name},{_id}.png" for _id, name, *_ in CATALOG]
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------- main

def main() -> None:
    validate()

    os.makedirs(ICON_DIR, exist_ok=True)

    metadata_csv = build_metadata_csv()
    icons_csv = build_icons_csv()

    with open(os.path.join(OUT_DIR, "AchievementsMetadata.csv"), "w", newline="\n") as fh:
        fh.write(metadata_csv)
    with open(os.path.join(OUT_DIR, "AchievementsIconsMappings.csv"), "w", newline="\n") as fh:
        fh.write(icons_csv)

    for _id, _name, _desc, _points, _inc, _steps, _hidden, track in CATALOG:
        make_icon(os.path.join(ICON_DIR, f"{_id}.png"), TRACK_COLORS[track])

    zip_path = os.path.join(OUT_DIR, ZIP_NAME)
    # No subdirectories inside the archive: every entry is a bare filename.
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("AchievementsMetadata.csv", metadata_csv)
        zf.writestr("AchievementsIconsMappings.csv", icons_csv)
        for _id, *_rest in CATALOG:
            zf.write(os.path.join(ICON_DIR, f"{_id}.png"), arcname=f"{_id}.png")

    # Post-build audit against the documented ZIP limits.
    with zipfile.ZipFile(zip_path) as zf:
        names = zf.namelist()
        assert len(names) == len(CATALOG) + 2, names
        assert len(names) <= 403
        assert len(set(names)) == len(names), "duplicate archive entries"
        for info in zf.infolist():
            assert "/" not in info.filename, f"subdirectory entry: {info.filename}"
            assert info.file_size < 1_000_000, f"{info.filename} is >= 1MB"
    assert os.path.getsize(zip_path) < 800 * 1024 * 1024

    print(f"OK  {len(CATALOG)} achievements, {sum(r[3] for r in CATALOG)} points")
    print(f"    {zip_path} ({os.path.getsize(zip_path) / 1024:.0f} KB, {len(names)} entries)")


if __name__ == "__main__":
    main()
