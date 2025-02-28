#!/usr/bin/env python3
"""
Python TextFSM Test Script

This script tests templates using the original Python TextFSM implementation
for comparison with the JavaScript port.
"""

import os
import sys
import time
import glob
import textfsm
import traceback
from concurrent.futures import ProcessPoolExecutor, as_completed

# Configuration
TEMPLATE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'templates')
TEST_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'tests')
VENDOR = 'cisco_ios'
TEMPLATE_PREFIX = 'cisco_ios'
MAX_WORKERS = 1  # Process sequentially

# Stats collection
stats = {
    'total': 0,
    'success': 0,
    'failed': 0,
    'skipped': 0,
    'times': [],
    'errors': []
}


def find_templates():
    """Find all template files"""
    pattern = os.path.join(TEMPLATE_DIR, f'{TEMPLATE_PREFIX}*.textfsm')
    templates = glob.glob(pattern)
    template_files = [os.path.basename(t) for t in templates]
    print(f"Found {len(template_files)} {TEMPLATE_PREFIX} templates")
    return template_files


def find_raw_file(command_name):
    """Find raw file for a command"""
    # Check in the most likely location first
    dir_path = os.path.join(TEST_DIR, VENDOR, command_name)
    if os.path.isdir(dir_path):
        # Get all files with .raw extension in the directory
        raw_files = [f for f in os.listdir(dir_path) if f.endswith('.raw')]
        if raw_files:
            return os.path.join(dir_path, raw_files[0])

    # If the directory doesn't exist or has no .raw files, search more broadly
    vendor_dir = os.path.join(TEST_DIR, VENDOR)
    try:
        directories = [d for d in os.listdir(vendor_dir) if os.path.isdir(os.path.join(vendor_dir, d))]

        # Look for a directory that might match
        possible_dirs = [d for d in directories if command_name in d or d in command_name]

        for directory in possible_dirs:
            dir_path = os.path.join(vendor_dir, directory)
            raw_files = [f for f in os.listdir(dir_path) if f.endswith('.raw')]

            if raw_files:
                return os.path.join(dir_path, raw_files[0])
    except:
        pass

    return None


def process_template(template_file):
    """Process a single template"""
    stats['total'] += 1
    template_path = os.path.join(TEMPLATE_DIR, template_file)
    command_name = os.path.basename(template_file).replace('.textfsm', '').replace(f'{TEMPLATE_PREFIX}_', '')

    print(f"\nTesting template: {template_file}")

    try:
        # Find the raw file
        raw_file = find_raw_file(command_name)
        if not raw_file:
            print(f"[SKIP] {command_name}: No matching raw file found")
            stats['skipped'] += 1
            return

        # Load template and raw data
        with open(template_path, 'r') as f:
            template_content = f.read()

        with open(raw_file, 'r') as f:
            raw_content = f.read()

        # Parse with TextFSM
        start_time = time.time()
        try:
            # Create template and parse
            template = textfsm.TextFSM(open(template_path))
            result = template.ParseText(raw_content)

            # Calculate execution time
            execution_time_ms = (time.time() - start_time) * 1000

            # Record success
            print(f"[PASS] {command_name}: Parsed {len(result)} records in {execution_time_ms:.2f}ms")
            stats['success'] += 1
            stats['times'].append({
                'template': template_file,
                'command': command_name,
                'time': execution_time_ms,
                'records': len(result)
            })

        except Exception as e:
            # Record failure
            error_msg = str(e)
            traceback_str = traceback.format_exc()
            print(f"[FAIL] {command_name}: {error_msg}")
            stats['failed'] += 1
            stats['errors'].append({
                'template': template_file,
                'command': command_name,
                'error': error_msg,
                'traceback': traceback_str
            })

    except Exception as e:
        # File read error
        print(f"[ERROR] {command_name}: {str(e)}")
        stats['failed'] += 1
        stats['errors'].append({
            'template': template_file,
            'command': command_name,
            'error': str(e)
        })


def print_summary():
    """Print summary statistics"""
    print('\n' + '=' * 50)
    print('Python TextFSM Testing Summary')
    print('=' * 50)

    print(f"\nTotal templates tested: {stats['total']}")
    success_rate = (stats['success'] / stats['total']) * 100 if stats['total'] > 0 else 0
    fail_rate = (stats['failed'] / stats['total']) * 100 if stats['total'] > 0 else 0
    skip_rate = (stats['skipped'] / stats['total']) * 100 if stats['total'] > 0 else 0

    print(f"Successful: {stats['success']} ({success_rate:.1f}%)")
    print(f"Failed: {stats['failed']} ({fail_rate:.1f}%)")
    print(f"Skipped: {stats['skipped']} ({skip_rate:.1f}%)")

    if stats['times']:
        # Calculate average time
        total_time = sum(item['time'] for item in stats['times'])
        avg_time = total_time / len(stats['times']) if stats['times'] else 0

        print(f"\nAverage parse time: {avg_time:.2f}ms")

        # Sort by time and get fastest/slowest
        stats['times'].sort(key=lambda x: x['time'])

        print('\nFastest templates:')
        for item in stats['times'][:5]:
            print(f"  {item['command']}: {item['time']:.2f}ms ({item['records']} records)")

        print('\nSlowest templates:')
        for item in reversed(stats['times'][-5:]):
            print(f"  {item['command']}: {item['time']:.2f}ms ({item['records']} records)")

    if stats['errors']:
        print('\nFailed templates:')
        for item in stats['errors']:
            print(f"  {item['command']}: {item['error']}")

    # Print overall assessment
    print('\n' + '=' * 50)
    if success_rate == 100:
        print('✅ All templates passed!')
    elif success_rate >= 90:
        print('🟢 Most templates are working correctly.')
    elif success_rate >= 75:
        print('🟡 The majority of templates are working, but some need attention.')
    else:
        print('🔴 Several templates need attention.')
    print('=' * 50)


def main():
    """Main execution function"""
    print('=== Python TextFSM Batch Testing ===')

    # Find templates
    templates = find_templates()
    if not templates:
        print('No templates found. Exiting.')
        sys.exit(1)

    # Process templates with a process pool
    if MAX_WORKERS > 1:
        with ProcessPoolExecutor(max_workers=MAX_WORKERS) as executor:
            futures = {executor.submit(process_template, template): template for template in templates}
            for future in as_completed(futures):
                try:
                    future.result()
                except Exception as exc:
                    template = futures[future]
                    print(f'Template {template} generated an exception: {exc}')
    else:
        # Process sequentially
        for template in templates:
            process_template(template)

    # Print summary
    print_summary()


if __name__ == "__main__":
    main()