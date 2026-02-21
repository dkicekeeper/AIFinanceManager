#!/usr/bin/env python3
"""
Migrate project.pbxproj: replace 18 Overpass static fonts with 2 Inter variable fonts.
Run from repo root: python3 Scripts/migrate_fonts.py
"""

INTER_REF          = "AA0001002F477D4A0010A953"
INTER_ITALIC_REF   = "AA0002002F477D4A0010A953"
INTER_BUILD        = "AA0003002F477D4A0010A953"
INTER_ITALIC_BUILD = "AA0004002F477D4A0010A953"
FONTS_GROUP_UUID   = "D69F99D72F477D4A0010A953"
RESOURCES_UUID     = "D62A098F2F0D7B0D004AF1FA"

INTER_FILE          = "Inter-VariableFont_opsz,wght.ttf"
INTER_ITALIC_FILE   = "Inter-Italic-VariableFont_opsz,wght.ttf"

PBXPROJ = "AIFinanceManager.xcodeproj/project.pbxproj"

with open(PBXPROJ) as f:
    content = f.read()

# -- 1. Remove ALL Overpass lines ----------------------------------------------
content = "".join(
    line for line in content.splitlines(keepends=True)
    if "Overpass" not in line
)

# -- 2. Insert Inter PBXBuildFile entries (right after section marker) ---------
inter_build = (
    f'\t\t{INTER_BUILD} /* {INTER_FILE} in Resources */ = '
    f'{{isa = PBXBuildFile; fileRef = {INTER_REF} /* {INTER_FILE} */; }};\n'
    f'\t\t{INTER_ITALIC_BUILD} /* {INTER_ITALIC_FILE} in Resources */ = '
    f'{{isa = PBXBuildFile; fileRef = {INTER_ITALIC_REF} /* {INTER_ITALIC_FILE} */; }};\n'
)
content = content.replace(
    "/* Begin PBXBuildFile section */\n",
    "/* Begin PBXBuildFile section */\n" + inter_build,
    1,
)

# -- 3. Insert Inter PBXFileReference entries ----------------------------------
inter_refs = (
    f'\t\t{INTER_REF} /* {INTER_FILE} */ = '
    f'{{isa = PBXFileReference; lastKnownFileType = file; path = "{INTER_FILE}"; sourceTree = "<group>"; }};\n'
    f'\t\t{INTER_ITALIC_REF} /* {INTER_ITALIC_FILE} */ = '
    f'{{isa = PBXFileReference; lastKnownFileType = file; path = "{INTER_ITALIC_FILE}"; sourceTree = "<group>"; }};\n'
)
content = content.replace(
    "/* Begin PBXFileReference section */\n",
    "/* Begin PBXFileReference section */\n" + inter_refs,
    1,
)

# -- 4. Populate Fonts PBXGroup children (was empty after step 1) --------------
inter_children = (
    f'\t\t\t\t{INTER_REF} /* {INTER_FILE} */,\n'
    f'\t\t\t\t{INTER_ITALIC_REF} /* {INTER_ITALIC_FILE} */,\n'
)
content = content.replace(
    f'{FONTS_GROUP_UUID} /* Fonts */ = {{\n'
    '\t\t\tisa = PBXGroup;\n'
    '\t\t\tchildren = (\n'
    '\t\t\t);',
    f'{FONTS_GROUP_UUID} /* Fonts */ = {{\n'
    '\t\t\tisa = PBXGroup;\n'
    '\t\t\tchildren = (\n'
    + inter_children +
    '\t\t\t);',
    1,
)

# -- 5. Populate main-target Resources build phase ----------------------------
inter_resources = (
    f'\t\t\t\t{INTER_BUILD} /* {INTER_FILE} in Resources */,\n'
    f'\t\t\t\t{INTER_ITALIC_BUILD} /* {INTER_ITALIC_FILE} in Resources */,\n'
)
content = content.replace(
    f'{RESOURCES_UUID} /* Resources */ = {{\n'
    '\t\t\tisa = PBXResourcesBuildPhase;\n'
    '\t\t\tbuildActionMask = 2147483647;\n'
    '\t\t\tfiles = (\n'
    '\t\t\t);',
    f'{RESOURCES_UUID} /* Resources */ = {{\n'
    '\t\t\tisa = PBXResourcesBuildPhase;\n'
    '\t\t\tbuildActionMask = 2147483647;\n'
    '\t\t\tfiles = (\n'
    + inter_resources +
    '\t\t\t);',
    1,
)

with open(PBXPROJ, "w") as f:
    f.write(content)

remaining = content.count("Overpass")
inter_count = content.count("Inter")
print(f"  project.pbxproj updated")
print(f"    Remaining 'Overpass' references: {remaining}  (expected 0)")
print(f"    'Inter' references: {inter_count}  (expected 8)")
assert remaining == 0, f"FAIL: {remaining} Overpass references remain"
