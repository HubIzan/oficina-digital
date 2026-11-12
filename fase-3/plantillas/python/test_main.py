# Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
import unittest

from main import saludo


class TestSaludo(unittest.TestCase):
    def test_saludo(self):
        self.assertIn("__NOMBRE__", saludo())


if __name__ == "__main__":
    unittest.main()
