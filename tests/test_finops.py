"""Check FinOps fail-closed behavior without credentials or cloud calls."""
from decimal import Decimal
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
    def test_azure_retail_applies_the_load_balancer_bundle_once(self):
        def row(product, meter, unit, amount, **attrs):
            return dict(productName=product, meterName=meter, unitOfMeasure=unit,
                        retailPrice=Decimal(amount), type="Consumption", currencyCode="EUR",
                        tierMinimumUnits=0, **attrs)

        with patch.object(cost, "retail_prices", side_effect=[
            [row("Load Balancer", cost.LB_METER, "1 Hour", "0.0224", armRegionName="Global", skuName="Standard")],
            [row("Virtual Machines Basv2 Series", "B2ats v2", "1 Hour", "0.011")],
            [row("Premium SSD Managed Disks", "P6 LRS Disk", "1/Month", "10.0787"),
             row("Standard SSD Managed Disks", "E3 LRS Disk", "1/Month", "1.0772")],
            [row("IP Addresses", "Standard IPv4 Static Public IP", "1 Hour", "0.0045", skuName="Standard")],
        ]):
            self.assertEqual(cost.azure_retail_monthly(cost.azure_lb_monthly()), Decimal("75.0403"))


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
    def test_preflight_detects_both_staging_providers_without_creating_runs(self):
        counts = {"dev-azure": 24, "dev-ovh": 0, "staging-azure": 24, "staging-ovh": 12, "prod-ovh": 12}
        with patch.multiple(release, workspace=lambda name: name,
                            managed_count=counts.__getitem__, compatible_version=Mock(),
                            execute=Mock()):
            with self.assertRaisesRegex(ValueError, "staging: both providers"):
                release.preflight(include_prod=True)
            self.assertEqual(release.compatible_version.call_count, 5)
            release.execute.assert_not_called()


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
                            workspace=lambda name: {"id": name, "attributes": {"allow-destroy-plan": True}},
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

    def test_rehearsal_previews_winner_without_destroying_active_provider(self):
        states = {"staging-azure": 24, "staging-ovh": 0}
        with patch.multiple(release, managed_count=states.__getitem__,
                            workspace=lambda name: name,
                            compatible_version=lambda name: "cv",
                            execute=Mock()):
            release.deploy("staging", "ovh", False, plan_only=True)
            release.execute.assert_called_once_with("staging-ovh", "cv", operation="preview")

    def test_production_rehearsal_never_applies(self):
        with patch.multiple(release, workspace=lambda name: name,
                            compatible_version=lambda name: "cv",
                            execute=Mock(), managed_count=Mock()):
            release.deploy("prod", "ovh", False, plan_only=True)
            release.execute.assert_called_once_with("prod-ovh", "cv", operation="preview")
            release.managed_count.assert_not_called()

    def test_both_active_is_rejected(self):
        with patch.object(release, "managed_count", return_value=1), patch.object(release, "execute") as execute:
            with self.assertRaisesRegex(ValueError, "both providers"):
                release.deploy("staging", "azure", True)
            execute.assert_not_called()


class HcpRunTest(unittest.TestCase):
    workspace = {"id": "ws-staging", "attributes": {"name": "staging-azure"}}

    def test_preview_never_confirms_apply(self):
        api = Mock(side_effect=[
            {"data": {"id": "run-preview"}},
            {"data": {"attributes": {"status": "planned_and_finished"}}},
        ])
        with patch.object(release, "api", api), patch.dict(release.os.environ, {"GITHUB_RUN_ID": "123"}):
            release.execute(self.workspace, "cv-preview", operation="preview")
        payload = api.call_args_list[0].args[1]["data"]["attributes"]
        self.assertTrue(payload["plan-only"])
        self.assertFalse(payload["auto-apply"])
        self.assertEqual([call.args[0] for call in api.call_args_list],
                         ["/runs", "/runs/run-preview"])

    def test_deploy_discards_a_plan_that_replaces_resources(self):
        api = Mock(side_effect=[
            {"data": {"id": "run-deploy"}},
            {"data": {"attributes": {"status": "planned", "actions": {"is-confirmable": True}},
                      "relationships": {"plan": {"data": {"id": "plan-replace"}}}}},
            {"data": {"attributes": {"resource-destructions": 1}}},
            None,
        ])
        with patch.object(release, "api", api), patch.object(release, "drain_vcs_plans"), \
                patch.dict(release.os.environ, {"GITHUB_RUN_ID": "123"}):
            with self.assertRaisesRegex(ValueError, "delete or replace"):
                release.execute(self.workspace, "cv-deploy", operation="deploy")
        self.assertEqual(api.call_args_list[-1].args[0], "/runs/run-deploy/actions/discard")


if __name__ == "__main__":
    unittest.main()
