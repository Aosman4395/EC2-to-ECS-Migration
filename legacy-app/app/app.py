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

from storage import create_storage, ProductNotFound, InsufficientStock


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


storage = create_storage(os.getenv('STORAGE_BACKEND', 'memory'))


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


@app.route('/ready', methods=['GET'])
def ready():
    """Check the selected storage without changing application data."""
    try:
        storage.check_ready()
    except Exception:
        logger.exception("Storage readiness check failed")
        return jsonify({"status": "not_ready", "storage": storage.name}), 503
    return jsonify({"status": "ready", "storage": storage.name}), 200


@app.route('/api/v1/products', methods=['GET'])
def get_products():
    products = storage.get_products()
    return jsonify({"products": products, "count": len(products)}), 200


@app.route('/api/v1/products/<int:product_id>', methods=['GET'])
def get_product(product_id):
    product = storage.get_product(product_id)
    if product is None:
        return jsonify({"error": "Product not found"}), 404
    return jsonify(product), 200


@app.route('/api/v1/orders', methods=['GET'])
def get_orders():
    orders = storage.get_orders()
    return jsonify({"orders": orders, "count": len(orders)}), 200


@app.route('/api/v1/orders', methods=['POST'])
def create_order():
    data = request.get_json()
    if not isinstance(data, dict) or not data:
        raise BadRequest("A non-empty JSON object is required")
    product_id = data.get('product_id')
    quantity = data.get('quantity', 1)
    if type(product_id) is not int or product_id <= 0:
        raise BadRequest("product_id must be a positive integer")
    if type(quantity) is not int or quantity <= 0:
        raise BadRequest("quantity must be a positive integer")
    try:
        order = storage.create_order(product_id, quantity)
    except ProductNotFound:
        return jsonify({"error": "Product not found"}), 404
    except InsufficientStock:
        return jsonify({"error": "Insufficient stock"}), 400
    return jsonify(order), 201


@app.route('/api/v1/stats', methods=['GET'])
def get_stats():
    stats = storage.get_stats()
    stats['timestamp'] = datetime.utcnow().isoformat()
    return jsonify(stats), 200


@app.errorhandler(BadRequest)
def bad_request(error):
    return jsonify({"error": str(error)}), 400


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

