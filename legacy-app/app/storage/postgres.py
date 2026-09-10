"""PostgreSQL storage for ECS. Schema must be provisioned before use."""
import os
from contextlib import contextmanager

import psycopg2
from psycopg2.extras import RealDictCursor

from . import InsufficientStock, ProductNotFound


class PostgresStorage:
    name = "postgres"

    def check_ready(self):
        with self.cursor() as cursor:
            cursor.execute("SET LOCAL statement_timeout = '5s'")
            # LIMIT 0 validates table/column access even when no rows exist.
            cursor.execute('SELECT id, name, price, stock FROM products LIMIT 0')
            cursor.execute("""
                SELECT id, product_id, quantity, total_price, created_at
                FROM orders LIMIT 0
            """)

    def __init__(self):
        required = ('DB_HOST', 'DB_NAME', 'DB_USER', 'DB_PASSWORD')
        missing = [name for name in required if not os.getenv(name)]
        if missing:
            raise ValueError('Missing PostgreSQL configuration: ' + ', '.join(missing))
        self.config = dict(
            host=os.environ['DB_HOST'],
            port=os.getenv('DB_PORT', '5432'),
            database=os.environ['DB_NAME'],
            user=os.environ['DB_USER'],
            password=os.environ['DB_PASSWORD'],
            connect_timeout=5,
            sslmode=os.getenv('DB_SSLMODE', 'require'),
        )

    @contextmanager
    def cursor(self):
        conn = psycopg2.connect(**self.config)
        try:
            # Commit on success, roll back on error, then always close.
            with conn:
                with conn.cursor(cursor_factory=RealDictCursor) as cursor:
                    yield cursor
        finally:
            conn.close()

    def get_products(self):
        with self.cursor() as cursor:
            cursor.execute('SELECT id, name, price, stock FROM products ORDER BY id')
            return cursor.fetchall()

    def get_product(self, product_id):
        with self.cursor() as cursor:
            cursor.execute(
                'SELECT id, name, price, stock FROM products WHERE id = %s',
                (product_id,),
            )
            return cursor.fetchone()

    def get_orders(self):
        with self.cursor() as cursor:
            cursor.execute("""
                SELECT o.id, o.product_id, p.name AS product_name,
                       o.quantity, o.total_price, o.created_at
                FROM orders o JOIN products p ON p.id = o.product_id
                ORDER BY o.id
            """)
            return cursor.fetchall()

    def create_order(self, product_id, quantity):
        with self.cursor() as cursor:
            cursor.execute(
                'SELECT id, name, price, stock FROM products WHERE id = %s FOR UPDATE',
                (product_id,),
            )
            product = cursor.fetchone()
            if product is None:
                raise ProductNotFound()
            if quantity > product['stock']:
                raise InsufficientStock()
            cursor.execute("""
                INSERT INTO orders (product_id, quantity, total_price)
                VALUES (%s, %s, %s)
                RETURNING id, product_id, quantity, total_price, created_at
            """, (product_id, quantity, product['price'] * quantity))
            order = cursor.fetchone()
            cursor.execute(
                'UPDATE products SET stock = stock - %s WHERE id = %s',
                (quantity, product_id),
            )
            order['product_name'] = product['name']
            return order

    def get_stats(self):
        with self.cursor() as cursor:
            cursor.execute('SELECT COUNT(*) AS total_products FROM products')
            products = cursor.fetchone()
            cursor.execute("""
                SELECT COUNT(*) AS total_orders,
                       COALESCE(SUM(total_price), 0) AS total_revenue FROM orders
            """)
            orders = cursor.fetchone()
            return {
                'total_products': products['total_products'],
                'total_orders': orders['total_orders'],
                'total_revenue': float(orders['total_revenue']),
            }
