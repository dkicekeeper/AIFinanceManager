#!/usr/bin/env python3
"""
Script to remove deprecated methods from TransactionsViewModel.swift

This script identifies and removes all methods marked with @available(*, deprecated)
while preserving the file structure and non-deprecated code.

Author: Claude Sonnet 4.5
Date: 2026-01-15
"""

import re
import sys
from pathlib import Path


def read_file(file_path):
    """Read the Swift file"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return f.read()
    except FileNotFoundError:
        print(f"❌ Error: File not found: {file_path}")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error reading file: {e}")
        sys.exit(1)


def write_file(file_path, content):
    """Write the cleaned Swift file"""
    try:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"✅ File written successfully: {file_path}")
    except Exception as e:
        print(f"❌ Error writing file: {e}")
        sys.exit(1)


def find_deprecated_methods(content):
    """
    Find all deprecated methods in the file.
    Returns list of tuples: (start_index, end_index, method_name)
    """
    deprecated_blocks = []
    lines = content.split('\n')

    i = 0
    while i < len(lines):
        line = lines[i]

        # Check if line contains @available(*, deprecated
        if '@available(*, deprecated' in line:
            # Found a deprecated method
            start_line = i

            # Find the method signature (next non-empty line after @available)
            j = i + 1
            while j < len(lines) and (lines[j].strip() == '' or lines[j].strip().startswith('//')):
                j += 1

            if j >= len(lines):
                i += 1
                continue

            method_signature = lines[j].strip()

            # Extract method name from signature
            method_name = "Unknown"
            if 'func ' in method_signature:
                match = re.search(r'func\s+(\w+)', method_signature)
                if match:
                    method_name = match.group(1)

            # Find the end of the method (matching closing brace)
            # We need to count braces to find the matching closing brace
            brace_count = 0
            found_opening = False
            end_line = j

            for k in range(j, len(lines)):
                line_text = lines[k]

                # Count opening and closing braces
                for char in line_text:
                    if char == '{':
                        brace_count += 1
                        found_opening = True
                    elif char == '}':
                        brace_count -= 1

                        # If we've found the opening brace and count is back to 0, we found the end
                        if found_opening and brace_count == 0:
                            end_line = k
                            break

                if found_opening and brace_count == 0:
                    break

            # Store the block to remove
            deprecated_blocks.append({
                'start': start_line,
                'end': end_line,
                'name': method_name,
                'lines': end_line - start_line + 1
            })

            print(f"📍 Found deprecated method: {method_name} (lines {start_line + 1}-{end_line + 1}, {end_line - start_line + 1} lines)")

            # Skip to end of this method
            i = end_line + 1
        else:
            i += 1

    return deprecated_blocks


def remove_deprecated_blocks(content, deprecated_blocks):
    """
    Remove deprecated blocks from the content.
    Returns cleaned content.
    """
    lines = content.split('\n')

    # Sort blocks by start line in reverse order (so we can remove from end to start)
    deprecated_blocks_sorted = sorted(deprecated_blocks, key=lambda x: x['start'], reverse=True)

    total_lines_removed = 0

    for block in deprecated_blocks_sorted:
        start = block['start']
        end = block['end']
        name = block['name']

        # Remove lines from start to end (inclusive)
        del lines[start:end + 1]

        lines_removed = end - start + 1
        total_lines_removed += lines_removed

        print(f"🗑️  Removed {name}: {lines_removed} lines")

    print(f"\n📊 Total lines removed: {total_lines_removed}")

    return '\n'.join(lines)


def clean_empty_lines(content):
    """
    Clean up excessive empty lines (more than 2 consecutive empty lines).
    """
    # Replace 3+ consecutive newlines with 2 newlines
    cleaned = re.sub(r'\n{3,}', '\n\n', content)
    return cleaned


def main():
    print("=" * 70)
    print("🔧 TransactionsViewModel.swift - Deprecated Methods Remover")
    print("=" * 70)
    print()

    # File path
    file_path = Path(__file__).parent / "AIFinanceManager" / "ViewModels" / "TransactionsViewModel.swift"

    if not file_path.exists():
        print(f"❌ Error: File not found: {file_path}")
        sys.exit(1)

    print(f"📂 File: {file_path}")
    print()

    # Read original file
    print("📖 Reading original file...")
    original_content = read_file(file_path)
    original_lines = len(original_content.split('\n'))
    print(f"   Original file: {original_lines} lines")
    print()

    # Find deprecated methods
    print("🔍 Searching for deprecated methods...")
    deprecated_blocks = find_deprecated_methods(original_content)
    print(f"\n   Found {len(deprecated_blocks)} deprecated methods")
    print()

    if not deprecated_blocks:
        print("✅ No deprecated methods found. Nothing to do.")
        return

    # Confirm removal
    print("⚠️  About to remove the following methods:")
    for block in deprecated_blocks:
        print(f"   - {block['name']} ({block['lines']} lines)")
    print()

    # Auto-confirm in non-interactive mode (for CLI execution)
    print("✅ Auto-confirming removal (non-interactive mode)")
    print()
    print("🗑️  Removing deprecated methods...")
    print()

    # Remove deprecated blocks
    cleaned_content = remove_deprecated_blocks(original_content, deprecated_blocks)

    # Clean up excessive empty lines
    print("🧹 Cleaning up empty lines...")
    cleaned_content = clean_empty_lines(cleaned_content)

    cleaned_lines = len(cleaned_content.split('\n'))
    lines_removed = original_lines - cleaned_lines
    percentage_removed = (lines_removed / original_lines) * 100

    print(f"\n📊 Summary:")
    print(f"   Original lines: {original_lines}")
    print(f"   Cleaned lines:  {cleaned_lines}")
    print(f"   Lines removed:  {lines_removed} ({percentage_removed:.1f}%)")
    print()

    # Write cleaned file
    print("💾 Writing cleaned file...")
    write_file(file_path, cleaned_content)
    print()

    print("=" * 70)
    print("✅ SUCCESS! Deprecated methods removed.")
    print("=" * 70)
    print()
    print("📝 Next steps:")
    print("   1. Build the project in Xcode to check for compilation errors")
    print("   2. Run the app on simulator to test basic functionality")
    print("   3. If there are issues, restore from backup:")
    print(f"      cp {file_path}.backup {file_path}")
    print()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n❌ Interrupted by user.")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
