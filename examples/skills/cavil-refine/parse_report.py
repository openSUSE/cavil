#!/usr/bin/env python3
"""
Parse Cavil legal reports and extract unresolved snippets into structured JSON.

Usage:
    python parse_report.py <report_file> [--output <output_file>]

The report_file can be either:
    - Raw JSON from mcp__cavil__cavil_get_report tool result
    - Plain markdown text of a Cavil report
"""

import json
import re
import sys
from pathlib import Path
from typing import List, Dict, Optional


def extract_markdown_from_json(file_path: str) -> str:
    """Extract markdown text from JSON tool result format."""
    try:
        with open(file_path, 'r') as f:
            data = json.load(f)

        # Handle array format: [{"type": "...", "text": "..."}]
        if isinstance(data, list) and len(data) > 0:
            if 'text' in data[0]:
                return data[0]['text']

        # Handle direct object format: {"text": "..."}
        if isinstance(data, dict) and 'text' in data:
            return data['text']

        # If it's already a string, return it
        if isinstance(data, str):
            return data

    except json.JSONDecodeError:
        # Not JSON, treat as plain text
        with open(file_path, 'r') as f:
            return f.read()

    raise ValueError("Could not extract markdown from file")


def parse_unresolved_snippets(markdown_text: str) -> List[Dict]:
    """Parse unresolved snippets from Cavil markdown report."""
    snippets = []

    # Find the Unmatched Keywords section
    unmatched_match = re.search(
        r'^## Unmatched Keywords\s*$',
        markdown_text,
        re.MULTILINE
    )

    if not unmatched_match:
        return snippets

    # Search to end of document — do NOT try to find the next ## section boundary,
    # because ## headings can appear inside snippet code blocks and would cause
    # premature cutoff (e.g. a README snippet containing "## Licensing").
    section_text = markdown_text[unmatched_match.end():]

    # Pattern to match snippet entries:
    # * `file_path` (Line: X Snippet: Y):
    # ```
    # code content
    # ```
    # Note: The closing ``` may be missing for the last snippet
    pattern = re.compile(
        r'\* `([^`]+)` \(Line: (\d+),? Snippet: (\d+)\):\s*\n```\n(.*?)(?:\n```|$)',
        re.DOTALL
    )

    for match in pattern.finditer(section_text):
        file_path, line_num, snippet_id, snippet_text = match.groups()

        snippets.append({
            "snippet_id": int(snippet_id),
            "file_path": file_path,
            "line": int(line_num),
            "text": snippet_text,
            "text_preview": snippet_text[:100].replace('\n', ' ') + ('...' if len(snippet_text) > 100 else '')
        })

    return snippets


def parse_license_predictions(markdown_text: str) -> Dict[str, List[Dict]]:
    """Parse Risk 9 (Unknown) entries from the Licenses section.

    These are the per-file predictions Cavil infers from the file path for files
    with unresolved snippets. Format inside `### Risk 9 (Unknown)`:
        * `file_path`: X% similarity to "License Name", estimated risk Y

    Other risk subsections list already-matched files and are not included here.
    A file may have multiple predictions; all are collected.
    """
    predictions: Dict[str, List[Dict]] = {}

    licenses_match = re.search(r'^## Licenses\s*$', markdown_text, re.MULTILINE)
    if not licenses_match:
        return predictions

    rest = markdown_text[licenses_match.end():]
    next_section = re.search(r'^## ', rest, re.MULTILINE)
    section_text = rest[:next_section.start()] if next_section else rest

    risk9_match = re.search(r'^### Risk 9\b[^\n]*$', section_text, re.MULTILINE)
    if not risk9_match:
        return predictions

    after_risk9 = section_text[risk9_match.end():]
    next_risk = re.search(r'^### ', after_risk9, re.MULTILINE)
    body = after_risk9[:next_risk.start()] if next_risk else after_risk9

    per_file_re = re.compile(
        r'^\* `([^`]+)`: ([\d.]+)% similarity to "([^"]+)", estimated risk (\d+)\s*$',
        re.MULTILINE
    )
    for m in per_file_re.finditer(body):
        file_path, similarity, license_name, est_risk = m.groups()
        predictions.setdefault(file_path, []).append({
            "license": license_name,
            "similarity": float(similarity),
            "estimated_risk": int(est_risk),
        })

    return predictions


def attach_predictions(snippets: List[Dict], predictions: Dict[str, List[Dict]]) -> None:
    """Attach license predictions to each snippet by exact file_path match."""
    for s in snippets:
        s["predictions"] = predictions.get(s["file_path"], [])


def extract_package_info(markdown_text: str) -> Dict[str, Optional[str]]:
    """Extract basic package information from report."""
    info = {
        "package_name": None,
        "package_id": None,
        "version": None,
        "state": None
    }

    # Extract Package name
    match = re.search(r'^Package: (.+)$', markdown_text, re.MULTILINE)
    if match:
        info["package_name"] = match.group(1)

    # Extract Package ID
    match = re.search(r'^Id: (\d+)$', markdown_text, re.MULTILINE)
    if match:
        info["package_id"] = match.group(1)

    # Extract Version
    match = re.search(r'^Version: (.+)$', markdown_text, re.MULTILINE)
    if match:
        info["version"] = match.group(1)

    # Extract State
    match = re.search(r'^State: (.+)$', markdown_text, re.MULTILINE)
    if match:
        info["state"] = match.group(1)

    return info


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description='Parse Cavil legal reports and extract unresolved snippets'
    )
    parser.add_argument('report_file', help='Path to Cavil report file (JSON or markdown)')
    parser.add_argument('--output', '-o', help='Output JSON file (default: stdout)')
    parser.add_argument('--pretty', action='store_true', help='Pretty-print JSON output')

    args = parser.parse_args()

    # Read and parse the report
    markdown_text = extract_markdown_from_json(args.report_file)
    package_info = extract_package_info(markdown_text)
    snippets = parse_unresolved_snippets(markdown_text)
    predictions = parse_license_predictions(markdown_text)
    attach_predictions(snippets, predictions)

    # Build output structure
    output = {
        "package": package_info,
        "unresolved_count": len(snippets),
        "unresolved": snippets
    }

    # Write output
    json_output = json.dumps(output, indent=2 if args.pretty else None)

    if args.output:
        with open(args.output, 'w') as f:
            f.write(json_output)
        print(f"Wrote {len(snippets)} unresolved snippets to {args.output}", file=sys.stderr)
    else:
        print(json_output)

    # Print summary to stderr
    if args.output or not sys.stdout.isatty():
        print(f"\nSummary:", file=sys.stderr)
        print(f"  Package: {package_info['package_name']} ({package_info['package_id']})", file=sys.stderr)
        print(f"  Unresolved snippets: {len(snippets)}", file=sys.stderr)


if __name__ == '__main__':
    main()
