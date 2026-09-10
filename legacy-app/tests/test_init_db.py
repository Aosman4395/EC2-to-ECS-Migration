import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'app'))
from init_db import initialize


class InitializationTests(unittest.TestCase):
    def test_refuses_memory_backend(self):
        with patch.dict(os.environ, {'STORAGE_BACKEND': 'memory'}):
            with self.assertRaises(ValueError):
                initialize()

    @patch.dict(os.environ, {'STORAGE_BACKEND': 'postgres'})
    @patch('storage.postgres.PostgresStorage')
    def test_schema_failure_propagates_without_success_check(self, storage_class):
        storage = storage_class.return_value
        cursor = storage.cursor.return_value.__enter__.return_value
        cursor.execute.side_effect = RuntimeError('schema denied')
        with self.assertRaises(RuntimeError):
            initialize()
        storage.check_ready.assert_not_called()

    @patch.dict(os.environ, {'STORAGE_BACKEND': 'postgres'})
    @patch('storage.postgres.PostgresStorage')
    def test_schema_is_loaded_and_checked_after_transaction(self, storage_class):
        storage = storage_class.return_value
        initialize()
        cursor = storage.cursor.return_value.__enter__.return_value
        sql = cursor.execute.call_args.args[0]
        self.assertIn('CREATE TABLE IF NOT EXISTS orders', sql)
        self.assertIn('ON CONFLICT (id) DO NOTHING', sql)
        storage.cursor.return_value.__exit__.assert_called_once_with(None, None, None)
        storage.check_ready.assert_called_once()
