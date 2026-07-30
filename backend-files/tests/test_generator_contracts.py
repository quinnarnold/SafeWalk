import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CITIES = ("atlanta", "boston", "chicago", "newyork", "philadelphia", "seattle")


def load_generator(city):
    path = ROOT / city / f"{city}.py"
    spec = importlib.util.spec_from_file_location(f"safewalk_{city}", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class GeneratorContractTests(unittest.TestCase):
    def test_od_pair_cache_is_scoped_to_requested_seed(self):
        for city in CITIES:
            with self.subTest(city=city):
                module = load_generator(city)
                module.BASE_DIR = Path("/tmp/safewalk-generator-test")
                self.assertEqual(
                    module.od_pairs_cache_path(7).name,
                    "OD_pairs_seed_7.csv",
                )
                self.assertNotEqual(
                    module.od_pairs_cache_path(7),
                    module.od_pairs_cache_path(8),
                )

    def test_new_york_uses_history_for_completed_years(self):
        module = load_generator("newyork")
        self.assertEqual(
            module.incident_api_for_year(2025, 2026),
            module.API_HISTORIC_URL,
        )
        self.assertEqual(
            module.incident_api_for_year(2026, 2026),
            module.API_YTD_URL,
        )


if __name__ == "__main__":
    unittest.main()
