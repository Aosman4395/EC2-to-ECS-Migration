"""
Legacy Flask Application
A simple Python Flask API running on EC2 behind Nginx.
This is the "before" state that students will migrate to ECS.
"""

import os
import logging
from datetime import datetime
from flask import Flask, jsonify, request
from werkzeug.exceptions import BadRequest

# added to new app for database storage
import psycopg2

# added to new app for database storage
from psycopg2.extras import RealDictCursor


# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# App metadata
APP_NAME = os.getenv('APP_NAME', 'legacy-api')
APP_VERSION = os.getenv('APP_VERSION', '1.0.0')
ENVIRONMENT = os.getenv('ENVIRONMENT', 'production')


# added to new app for database storage
# Database connection details are injected into the container
# through ECS environment variables and Secrets Manager.
DB_HOST = os.getenv('DB_HOST')
DB_PORT = os.getenv('DB_PORT', '5432')
DB_NAME = os.getenv('DB_NAME')
DB_USER = os.getenv('DB_USER')
DB_PASSWORD = os.getenv('DB_PASSWORD')


# added to new app for database storage
def get_db_connection():
    """
    Create a connection to the PostgreSQL database.
    """
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD
    )


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "service": APP_NAME,
        "version": APP_VERSION,
        "environment": ENVIRONMENT
    }), 200


@app.route('/api/v1/products', methods=['GET'])
def get_products():
    """Get all products"""
    logger.info("GET /api/v1/products")

    # added to new app for database storage
    conn = get_db_connection()
    cursor = conn.cursor(cursor_factory=RealDictCursor)

    # added to new app for database storage
    cursor.execute("""
        SELECT id, name, price, stock
        FROM products
        ORDER BY id
    """)

    # added to new app for database storage
    products = cursor.fetchall()

    # added to new app for database storage
    cursor.close()
    conn.close()

    return jsonify({
        "products": products,
        "count": len(products)
    }), 200


@app.route('/api/v1/products/<int:product_id>', methods=['GET'])
def get_product(product_id):
    """Get a specific product"""
    logger.info(f"GET /api/v1/products/{product_id}")

    # added to new app for database storage
    conn = get_db_connection()
    cursor = conn.cursor(cursor_factory=RealDictCursor)

    # added to new app for database storage
    cursor.execute(
        """
        SELECT id, name, price, stock
        FROM products
        WHERE id = %s
        """,
        (product_id,)
    )

    # added to new app for database storage
    product = cursor.fetchone()

    # added to new app for database storage
    cursor.close()
    conn.close()

    if not product:
        return jsonify({"error": "Product not found"}), 404

    return jsonify(product), 200


@app.route('/api/v1/orders', methods=['GET'])
def get_orders():
    """Get all orders"""
    logger.info("GET /api/v1/orders")

    # added to new app for database storage
    conn = get_db_connection()
    cursor = conn.cursor(cursor_factory=RealDictCursor)

    # added to new app for database storage
    cursor.execute("""
        SELECT
            o.id,
            o.product_id,
            p.name AS product_name,
            o.quantity,
            o.total_price,
            o.created_at
        FROM orders o
        JOIN products p
            ON p.id = o.product_id
        ORDER BY o.id
    """)

    # added to new app for database storage
    orders = cursor.fetchall()

    # added to new app for database storage
    cursor.close()
    conn.close()

    return jsonify({
        "orders": orders,
        "count": len(orders)
    }), 200


@app.route('/api/v1/orders', methods=['POST'])
def create_order():
    """Create a new order"""
    logger.info("POST /api/v1/orders")

    # added to new app for database storage
    conn = None

    try:
        data = request.get_json()

        if not data:
            raise BadRequest("No JSON data provided")

        product_id = data.get('product_id')
        quantity = data.get('quantity', 1)

        if not product_id:
            raise BadRequest("product_id is required")

        # added to new app for database storage
        if not isinstance(quantity, int) or quantity <= 0:
            raise BadRequest("quantity must be a positive integer")

        # added to new app for database storage
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)

        # added to new app for database storage
        # FOR UPDATE locks the product row while the order is being created.
        cursor.execute(
            """
            SELECT id, name, price, stock
            FROM products
            WHERE id = %s
            FOR UPDATE
            """,
            (product_id,)
        )

        # added to new app for database storage
        product = cursor.fetchone()

        if not product:
            # added to new app for database storage
            cursor.close()
            return jsonify({"error": "Product not found"}), 404

        if quantity > product['stock']:
            # added to new app for database storage
            cursor.close()
            return jsonify({"error": "Insufficient stock"}), 400

        # added to new app for database storage
        total_price = product['price'] * quantity

        # added to new app for database storage
        cursor.execute(
            """
            INSERT INTO orders (
                product_id,
                quantity,
                total_price
            )
            VALUES (%s, %s, %s)
            RETURNING
                id,
                product_id,
                quantity,
                total_price,
                created_at
            """,
            (
                product_id,
                quantity,
                total_price
            )
        )

        # added to new app for database storage
        order = cursor.fetchone()

        # added to new app for database storage
        cursor.execute(
            """
            UPDATE products
            SET stock = stock - %s
            WHERE id = %s
            """,
            (
                quantity,
                product_id
            )
        )

        # added to new app for database storage
        conn.commit()

        # added to new app for database storage
        order['product_name'] = product['name']

        # added to new app for database storage
        cursor.close()

        logger.info(f"Order created: {order['id']}")

        return jsonify(order), 201

    except BadRequest as e:
        return jsonify({"error": str(e)}), 400

    except Exception as e:
        # added to new app for database storage
        if conn:
            conn.rollback()

        logger.error(f"Error creating order: {str(e)}")
        return jsonify({"error": "Internal server error"}), 500

    finally:
        # added to new app for database storage
        if conn:
            conn.close()


@app.route('/api/v1/stats', methods=['GET'])
def get_stats():
    """Get application statistics"""
    logger.info("GET /api/v1/stats")

    # added to new app for database storage
    conn = get_db_connection()
    cursor = conn.cursor(cursor_factory=RealDictCursor)

    # added to new app for database storage
    cursor.execute("""
        SELECT COUNT(*) AS total_products
        FROM products
    """)

    # added to new app for database storage
    products_result = cursor.fetchone()

    # added to new app for database storage
    cursor.execute("""
        SELECT
            COUNT(*) AS total_orders,
            COALESCE(SUM(total_price), 0) AS total_revenue
        FROM orders
    """)

    # added to new app for database storage
    orders_result = cursor.fetchone()

    # added to new app for database storage
    cursor.close()
    conn.close()

    return jsonify({
        "total_products": products_result['total_products'],
        "total_orders": orders_result['total_orders'],

        # added to new app for database storage
        # PostgreSQL NUMERIC values are returned as Decimal objects,
        # so convert the value to float for JSON output.
        "total_revenue": float(orders_result['total_revenue']),

        "timestamp": datetime.utcnow().isoformat()
    }), 200


@app.errorhandler(404)
def not_found(error):
    return jsonify({"error": "Not found"}), 404


@app.errorhandler(500)
def internal_error(error):
    logger.error(f"Internal server error: {str(error)}")
    return jsonify({"error": "Internal server error"}), 500


if __name__ == '__main__':
    # This is for development only
    # Production uses gunicorn via wsgi.py
    app.run(host='0.0.0.0', port=5000, debug=False)

