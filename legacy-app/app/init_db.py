"""Run explicitly inside a task with RDS access: python init_db.py."""
import os
from pathlib import Path


def initialize():
    if os.getenv('STORAGE_BACKEND') != 'postgres':
        raise ValueError('Schema initialization requires STORAGE_BACKEND=postgres')
    from storage.postgres import PostgresStorage
    storage = PostgresStorage()
    with storage.cursor() as cursor:
        cursor.execute("SET LOCAL lock_timeout = '10s'")
        cursor.execute("SET LOCAL statement_timeout = '60s'")
        # Serialize concurrent invocations; released on commit or rollback.
        cursor.execute('SELECT pg_advisory_xact_lock(7348291)')
        cursor.execute(Path(__file__).with_name('schema.sql').read_text())
    storage.check_ready()


if __name__ == '__main__':
    initialize()
    print('Database schema and sample products are ready.')
