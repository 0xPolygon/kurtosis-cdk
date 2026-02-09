#!/usr/bin/env python3
"""
Unit tests for dump_to_alloc.py
"""

import json
import os
import sys
import tempfile
import unittest

# Add parent directory to path to import dump_to_alloc
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
from dump_to_alloc import normalize_address, to_hex, convert_account, dump_to_alloc


class TestNormalizeAddress(unittest.TestCase):
    def test_lowercase(self):
        self.assertEqual(normalize_address('0xABCD'), '0xabcd')

    def test_add_prefix(self):
        self.assertEqual(normalize_address('abcd'), '0xabcd')

    def test_already_normalized(self):
        self.assertEqual(normalize_address('0xabcd'), '0xabcd')

    def test_empty(self):
        self.assertIsNone(normalize_address(''))
        self.assertIsNone(normalize_address(None))


class TestToHex(unittest.TestCase):
    def test_int_to_hex(self):
        self.assertEqual(to_hex(0), '0x0')
        self.assertEqual(to_hex(255), '0xff')
        self.assertEqual(to_hex(1000), '0x3e8')

    def test_already_hex(self):
        self.assertEqual(to_hex('0x123'), '0x123')
        self.assertEqual(to_hex('abc'), '0xabc')


class TestConvertAccount(unittest.TestCase):
    def test_balance_only(self):
        account = {'balance': 1000}
        result = convert_account(account)
        self.assertIn('balance', result)
        self.assertEqual(result['balance'], hex(1000))

    def test_with_nonce(self):
        account = {'balance': 1000, 'nonce': 5}
        result = convert_account(account)
        self.assertEqual(result['nonce'], hex(5))

    def test_zero_nonce_omitted(self):
        account = {'balance': 1000, 'nonce': 0}
        result = convert_account(account)
        self.assertNotIn('nonce', result)

    def test_with_code(self):
        account = {'balance': 1000, 'code': '0x6080604052'}
        result = convert_account(account)
        self.assertEqual(result['code'], '0x6080604052')

    def test_empty_code_omitted(self):
        account = {'balance': 1000, 'code': '0x'}
        result = convert_account(account)
        self.assertNotIn('code', result)

    def test_with_storage(self):
        storage = {'0x00': '0x123', '0x01': '0x456'}
        account = {'balance': 1000, 'storage': storage}
        result = convert_account(account)
        self.assertEqual(result['storage'], storage)

    def test_empty_storage_omitted(self):
        account = {'balance': 1000, 'storage': {}}
        result = convert_account(account)
        self.assertNotIn('storage', result)


class TestDumpToAlloc(unittest.TestCase):
    def test_empty_dump(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            dump_file = os.path.join(tmpdir, 'dump.json')
            alloc_file = os.path.join(tmpdir, 'alloc.json')

            # Empty dump
            with open(dump_file, 'w') as f:
                json.dump({'accounts': {}}, f)

            dump_to_alloc(dump_file, alloc_file)

            with open(alloc_file, 'r') as f:
                alloc = json.load(f)

            self.assertEqual(alloc, {})

    def test_simple_accounts(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            dump_file = os.path.join(tmpdir, 'dump.json')
            alloc_file = os.path.join(tmpdir, 'alloc.json')

            # Dump with accounts
            dump = {
                'accounts': {
                    '0xABCD1234': {'balance': 1000},
                    '0xEF567890': {'balance': 2000, 'nonce': 3}
                }
            }
            with open(dump_file, 'w') as f:
                json.dump(dump, f)

            dump_to_alloc(dump_file, alloc_file)

            with open(alloc_file, 'r') as f:
                alloc = json.load(f)

            self.assertEqual(len(alloc), 2)
            self.assertIn('0xabcd1234', alloc)
            self.assertIn('0xef567890', alloc)
            self.assertEqual(alloc['0xabcd1234']['balance'], hex(1000))
            self.assertEqual(alloc['0xef567890']['nonce'], hex(3))

    def test_contract_with_storage(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            dump_file = os.path.join(tmpdir, 'dump.json')
            alloc_file = os.path.join(tmpdir, 'alloc.json')

            # Contract account
            dump = {
                'accounts': {
                    '0xCONTRACT': {
                        'balance': 0,
                        'code': '0x6080604052',
                        'storage': {
                            '0x0000000000000000000000000000000000000000000000000000000000000000': '0x0000000000000000000000000000000000000000000000000000000000000001'
                        }
                    }
                }
            }
            with open(dump_file, 'w') as f:
                json.dump(dump, f)

            dump_to_alloc(dump_file, alloc_file)

            with open(alloc_file, 'r') as f:
                alloc = json.load(f)

            self.assertEqual(len(alloc), 1)
            contract = alloc['0xcontract']
            self.assertIn('code', contract)
            self.assertIn('storage', contract)
            self.assertEqual(contract['code'], '0x6080604052')


if __name__ == '__main__':
    unittest.main()
