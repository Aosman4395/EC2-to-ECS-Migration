import os
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'app'))
os.environ['STORAGE_BACKEND'] = 'memory'
import app as api
from storage import create_storage, InsufficientStock
from storage.memory import MemoryStorage


class ApiTests(unittest.TestCase):
    def setUp(self):
        api.storage = MemoryStorage()
        self.client = api.app.test_client()

    def test_memory_order_lifecycle_without_database(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertIsInstance(create_storage('memory'), MemoryStorage)
        self.assertEqual(self.client.get('/health').status_code, 200)
        self.assertEqual(self.client.get('/api/v1/products').json['count'], 3)
        response = self.client.post('/api/v1/orders', json={'product_id': 1, 'quantity': 2})
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json['total_price'], 59.98)
        self.assertEqual(self.client.get('/api/v1/products/1').json['stock'], 98)
        self.assertEqual(self.client.get('/api/v1/orders').json['count'], 1)
        self.assertEqual(self.client.get('/api/v1/stats').json['total_revenue'], 59.98)

    def test_rejected_orders_do_not_change_stock(self):
        for payload, status in [
            ({'product_id': 999}, 404),
            ({'product_id': 1, 'quantity': 101}, 400),
            ({'product_id': 1, 'quantity': -1}, 400),
            ({'product_id': 1, 'quantity': True}, 400),
            ({'product_id': '1'}, 400),
            ({'quantity': 1}, 400),
            ([1], 400),
        ]:
            self.assertEqual(self.client.post('/api/v1/orders', json=payload).status_code, status)
        self.assertEqual(self.client.get('/api/v1/products/1').json['stock'], 100)
        self.assertEqual(self.client.get('/api/v1/orders').json['count'], 0)
        self.assertEqual(self.client.get('/api/v1/products/999').status_code, 404)

    def test_readiness_memory(self):
        response = self.client.get('/ready')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json, {'status': 'ready', 'storage': 'memory'})

    def test_readiness_database_failure_is_private(self):
        api.storage = MagicMock(name='postgres')
        api.storage.name = 'postgres'
        api.storage.check_ready.side_effect = RuntimeError('private connection details')
        with self.assertLogs('app', level='ERROR'):
            response = self.client.get('/ready')
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json, {'status': 'not_ready', 'storage': 'postgres'})
        self.assertEqual(self.client.get('/health').status_code, 200)

    def test_invalid_backend_fails(self):
        with self.assertRaises(ValueError):
            create_storage('postgre')

    def test_storage_failure_does_not_fall_back(self):
        api.storage = MagicMock()
        api.storage.get_products.side_effect = RuntimeError('database unavailable')
        response = self.client.get('/api/v1/products')
        self.assertEqual(response.status_code, 500)
        self.assertEqual(response.json, {'error': 'Internal server error'})


class PostgresTests(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {
            'DB_HOST': 'database', 'DB_NAME': 'migrationdb',
            'DB_USER': 'user', 'DB_PASSWORD': 'test-password',
        })
        self.env.start()
        self.addCleanup(self.env.stop)
        self.store = create_storage('postgres')

    @patch('storage.postgres.psycopg2.connect')
    def test_readiness_missing_table(self, connect):
        cursor = connect.return_value.cursor.return_value.__enter__.return_value
        cursor.execute.side_effect = [None, None, RuntimeError('orders missing')]
        api.storage = self.store
        with self.assertLogs('app', level='ERROR'):
            response = api.app.test_client().get('/ready')
        self.assertEqual(response.status_code, 503)
        connect.return_value.close.assert_called_once()

    @patch('storage.postgres.psycopg2.connect')
    def test_readiness_postgres_success(self, connect):
        api.storage = self.store
        response = api.app.test_client().get('/ready')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json['storage'], 'postgres')
        connect.return_value.close.assert_called_once()

    def test_missing_configuration_fails(self):
        with patch.dict(os.environ, {}, clear=True), self.assertRaises(ValueError):
            create_storage('postgres')

    @patch('storage.postgres.psycopg2.connect')
    def test_order_uses_transaction_and_closes_connection(self, connect):
        conn = connect.return_value
        cursor = conn.cursor.return_value.__enter__.return_value
        cursor.fetchone.side_effect = [
            {'id': 1, 'name': 'Widget A', 'price': 29.99, 'stock': 100},
            {'id': 1, 'product_id': 1, 'quantity': 2, 'total_price': 59.98},
        ]
        order = self.store.create_order(1, 2)
        self.assertEqual(order['product_name'], 'Widget A')
        self.assertIn('FOR UPDATE', cursor.execute.call_args_list[0].args[0])
        self.assertEqual(cursor.execute.call_args_list[-1].args[1], (2, 1))
        conn.__exit__.assert_called_once_with(None, None, None)
        conn.close.assert_called_once()

    @patch('storage.postgres.psycopg2.connect')
    def test_failed_order_exits_transaction_with_error_and_closes(self, connect):
        conn = connect.return_value
        cursor = conn.cursor.return_value.__enter__.return_value
        cursor.fetchone.return_value = {'stock': 0}
        with self.assertRaises(InsufficientStock):
            self.store.create_order(1, 1)
        self.assertEqual(cursor.execute.call_count, 1)
        self.assertIs(conn.__exit__.call_args.args[0], InsufficientStock)
        conn.close.assert_called_once()

    @patch('storage.postgres.psycopg2.connect')
    def test_query_failure_closes_connection(self, connect):
        conn = connect.return_value
        cursor = conn.cursor.return_value.__enter__.return_value
        cursor.execute.side_effect = RuntimeError('missing table')
        with self.assertRaises(RuntimeError):
            self.store.get_products()
        conn.close.assert_called_once()


if __name__ == '__main__':
    unittest.main()
