"""Storage selection. Database failures never fall back to memory."""


class ProductNotFound(Exception):
    pass


class InsufficientStock(Exception):
    pass


def create_storage(backend):
    if backend == 'memory':
        from .memory import MemoryStorage
        return MemoryStorage()
    if backend == 'postgres':
        from .postgres import PostgresStorage
        return PostgresStorage()
    raise ValueError(f"Unsupported STORAGE_BACKEND: {backend!r}")
