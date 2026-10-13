#!/usr/bin/env python3
# Copyright 2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
import argparse
import re
import sys
from pathlib import Path

VIOLATION_RE = re.compile(
    r'^\[\w+\]\s+'
    r'(?P<rule>\S+)\s+'
    r'(?:\([^)]*\)\s+|\S+\s+)?'
    r'(?P<severity>\S+)\s+'
    r'(?P<file>\S*/\S+|N\.A\.)\s+'
    r'(?P<line>\d+)\s+'
    r'\d+\s+'
    r'(?P<message>.*?)\s*$'
)
WAIVERS = [
    # unsigned argument passed to $unsigned system function
    'WRN_1024',
    # flop enable pin is constant
    'FlopEConst',
    # operand width mismatch across arithmetic/comparison operators
    'W116',
    # input declared but not read
    'W240',
    # instance output port left unconnected
    'W287b',
    # operand width mismatch across relational operators
    'W362',
    # signal assigned multiple times in the same always block
    'W415a',
    # based number literal contains don't-care (?), sim/synth mismatch risk
    'W467',
    # shift result wider than LHS truncates bits
    'W486',
    # variable assigned but never read
    'W528'
]
RTL_DIR = Path(__file__).resolve().parents[2] / 'rtl'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('report', help='Path to moresimple.rpt')
    args = parser.parse_args()

    with open(args.report) as f:
        violations = [m.groupdict() for m in map(VIOLATION_RE.match, f) if m]
    print(f'Read {len(violations)} violations.')

    violations = [v for v in violations if v['severity'] != 'Info']
    print(f'Ignore info messages. {len(violations)} messages remaining.')

    # Waive safe to ignore rules
    violations = [v for v in violations if v['rule'] not in WAIVERS]
    print(f'Waive {", ".join(WAIVERS)}. {len(violations)} messages remaining.')

    # The dependencies run their own lint, so only the datamover RTL can fail this check.
    own = [v for v in violations
           if v['file'] != 'N.A.' and RTL_DIR in Path(v['file']).resolve().parents]
    print(f'Keep only violations in {RTL_DIR}. {len(own)} messages remaining, '
          f'{len(violations) - len(own)} in the dependencies.')

    if own:
        print(f'FAIL: {len(own)} violation(s) found')
        for v in own:
            print(f"  [{v['severity']}] {v['rule']}  {v['file']}:{v['line']}  {v['message']}")
        sys.exit(1)
    print('PASS')


if __name__ == '__main__':
    main()
