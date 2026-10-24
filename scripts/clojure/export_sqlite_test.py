import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('export_sqlite', Path(__file__).with_name('export_sqlite.py'))
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)

class ExportTest(unittest.TestCase):
    def test_preserves_blob_and_does_not_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            database, output = Path(directory)/'source.sqlite3', Path(directory)/'snapshot.json'
            with sqlite3.connect(database) as connection:
                connection.execute('CREATE TABLE documents(id INTEGER PRIMARY KEY, content BLOB)')
                connection.execute('INSERT INTO documents VALUES(1,?)', (b'\x00\xff\x01',))
            self.assertEqual(exporter.export(database, output), {'documents': 1})
            self.assertEqual(json.loads(output.read_text())['tables']['documents'][0]['content'], {'$binary': 'AP8B'})
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError): exporter.export(database, output)
            with sqlite3.connect(database) as connection:
                self.assertEqual(connection.execute('SELECT content FROM documents').fetchone()[0], b'\x00\xff\x01')

if __name__ == '__main__': unittest.main()
