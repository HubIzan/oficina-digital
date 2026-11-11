import unittest

from main import saludo


class TestSaludo(unittest.TestCase):
    def test_saludo(self):
        self.assertIn("__NOMBRE__", saludo())


if __name__ == "__main__":
    unittest.main()
