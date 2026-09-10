"""Legacy storage: data is local to each worker and resets on restart."""
from datetime import datetime
from threading import RLock

from . import InsufficientStock, ProductNotFound


class MemoryStorage:
    name = "memory"

    def check_ready(self):
        self.get_products()
        self.get_orders()

    def __init__(self):
        self.products = {
            1: {"id": 1, "name": "Widget A", "price": 29.99, "stock": 100},
            2: {"id": 2, "name": "Widget B", "price": 39.99, "stock": 50},
            3: {"id": 3, "name": "Widget C", "price": 49.99, "stock": 75},
        }
        self.orders = []
        self.lock = RLock()

    def get_products(self):
        with self.lock:
            return [dict(product) for product in self.products.values()]

    def get_product(self, product_id):
        with self.lock:
            product = self.products.get(product_id)
            return dict(product) if product is not None else None

    def get_orders(self):
        with self.lock:
            return [dict(order) for order in self.orders]

    def create_order(self, product_id, quantity):
        with self.lock:
            product = self.products.get(product_id)
            if product is None:
                raise ProductNotFound()
            if quantity > product['stock']:
                raise InsufficientStock()
            order = {
                'id': len(self.orders) + 1,
                'product_id': product_id,
                'product_name': product['name'],
                'quantity': quantity,
                'total_price': product['price'] * quantity,
                'created_at': datetime.utcnow().isoformat(),
            }
            self.orders.append(order)
            product['stock'] -= quantity
            return dict(order)

    def get_stats(self):
        with self.lock:
            return {
                'total_products': len(self.products),
                'total_orders': len(self.orders),
                'total_revenue': sum(order['total_price'] for order in self.orders),
            }
