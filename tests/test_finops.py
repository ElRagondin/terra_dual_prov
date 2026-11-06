"""Check FinOps fail-closed behavior without credentials or cloud calls."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).resolve().parents[1] / "scripts" / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


cost = load("staging-cost")
release = load("hcp-release")


class PricingTest(unittest.TestCase):
    def test_hourly_catalog_rates_and_missing_cost(self):
        selectors = {name: name for name in cost.QUANTITIES}
        catalog = {"plans": [{"planCode": name, "pricings": [
            {"interval": 1, "intervalUnit": "hour", "capacities": ["consumption"], "price": 1_000_000}
        ]} for name in selectors]}
        self.assertEqual(cost.ovh_monthly(catalog, selectors), cost.HOURS * sum(cost.QUANTITIES.values()) / 100)
        catalog["plans"][-1]["pricings"][0].update(interval=0, intervalUnit="none")
        self.assertEqual(cost.ovh_monthly(catalog, selectors), cost.HOURS * sum(cost.QUANTITIES.values()) / 100)
        catalog["plans"].pop()
        with self.assertRaisesRegex(ValueError, "Missing or ambiguous"):
            cost.ovh_monthly(catalog, selectors)

    def test_azure_requires_all_billable_resources(self):
        resources = [{"resourceType": kind, "monthlyCost": "1", "costComponents": [{"monthlyCost": "0.5"}], "subresources": [{"monthlyCost": "0.5"}]}
                     for kind, count in cost.AZURE_COUNTS.items() for _ in range(count)]
        report = {"currency": "EUR", "totalMonthlyCost": "6", "projects": [{"breakdown": {"resources": resources}}]}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "cost.json"
            path.write_text(json.dumps(report))
            self.assertEqual(cost.azure_monthly(path), 6)
            resources.pop()
            path.write_text(json.dumps(report))
            with self.assertRaisesRegex(ValueError, "coverage"):
                cost.azure_monthly(path)


class PromotionTest(unittest.TestCase):
    def test_switch_waits_for_destroy_and_empty_state(self):
        operations = []
        state = {"staging-ovh": 15, "staging-azure": 0}

        def execute(workspace, version, *, operation, before_apply=None):
            operations.append((workspace, operation))
            if before_apply:
                before_apply()
            if operation == "destroy":
                state[workspace] = 0
            if operation == "deploy":
                state[workspace] = 24

        def invoke(workspace, *args, **kwargs):
            execute(workspace["id"], *args, **kwargs)

        with patch.multiple(release, managed_count=state.__getitem__,
                            workspace=lambda name: {"id": name},
                            compatible_version=lambda workspace: "cv", execute=invoke,
                            drain_vcs_plans=Mock(), api=Mock(return_value={"data": []})):
            release.deploy("staging", "azure", True)
        self.assertEqual(operations, [("staging-azure", "preview"),
                                      ("staging-ovh", "destroy"), ("staging-azure", "deploy")])

    def test_switch_requires_explicit_permission(self):
        with patch.multiple(release, managed_count=lambda name: int(name.endswith("ovh")),
                            workspace=Mock(), compatible_version=Mock(), execute=Mock()):
            with self.assertRaisesRegex(ValueError, "allow_switch"):
                release.deploy("staging", "azure", False)
            release.execute.assert_not_called()

    def test_both_active_is_rejected(self):
        with patch.object(release, "managed_count", return_value=1), patch.object(release, "execute") as execute:
            with self.assertRaisesRegex(ValueError, "both providers"):
                release.deploy("staging", "azure", True)
            execute.assert_not_called()


if __name__ == "__main__":
    unittest.main()
