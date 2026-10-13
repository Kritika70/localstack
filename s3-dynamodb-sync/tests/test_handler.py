import io
import unittest

from terraform.function.handler import csv_rows


class CsvRowsTests(unittest.TestCase):
    def test_converts_rows_to_items_with_source_and_row_keys(self):
        rows = list(csv_rows(io.BytesIO(b"id,name\n1,Ada\n2,Linus\n"), "people.csv"))

        self.assertEqual(
            rows,
            [
                {"source_key": "people.csv", "row_number": 1, "id": "1", "name": "Ada"},
                {"source_key": "people.csv", "row_number": 2, "id": "2", "name": "Linus"},
            ],
        )

    def test_header_only_file_has_no_rows(self):
        self.assertEqual(
            list(csv_rows(io.BytesIO(b"id,name\n"), "empty.csv")),
            [],
        )

    def test_rejects_duplicate_headers(self):
        with self.assertRaisesRegex(ValueError, "duplicate"):
            list(csv_rows(io.BytesIO(b"id,id\n1,2\n"), "duplicate.csv"))

    def test_rejects_reserved_headers(self):
        with self.assertRaisesRegex(ValueError, "reserved"):
            list(csv_rows(io.BytesIO(b"source_key,name\nfile.csv,Ada\n"), "file.csv"))


if __name__ == "__main__":
    unittest.main()
