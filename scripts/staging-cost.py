"""Compare the hourly-list-price baseline for the deployed staging topology."""
import argparse
from collections import Counter
from decimal import Decimal
import json
import os
from pathlib import Path
import re
from urllib.request import urlopen

CATALOG = "https://eu.api.ovh.com/1.0/order/catalog/public/cloud?ovhSubsidiary=FR"
HOURS = Decimal(730)
# Price the current GRA11 topology; the catalog currently prices C3 local storage at zero.
QUANTITIES = {
    "c3-4": 3, "boot-storage": 150, "pgdata-classic": 10,
    "load-balancer-small": 1, "floating-ip": 2,
}
OVH_CODES = {
    "c3-4": "c3-4.consumption",
    "boot-storage": "instance.local-storage-gen3-gb.hour.consumption",
    "pgdata-classic": "volume.classic.consumption",
    "load-balancer-small": "octavia-loadbalancer.loadbalancer-s.hour.consumption",
    "floating-ip": "floatingip.floatingip.hour.consumption",
}
AZURE_COUNTS = {
    "azurerm_linux_virtual_machine": 3, "azurerm_managed_disk": 1,
    "azurerm_lb": 1, "azurerm_public_ip": 1,
}


def azure_monthly(path):
    report = json.loads(path.read_text())
    if report["currency"] != "EUR" or len(report["projects"]) != 1:
        raise ValueError("Expected a single Azure project priced in EUR")
    resources = report["projects"][0]["breakdown"]["resources"]
    paid = [row for row in resources if row.get("monthlyCost") is not None
            and Decimal(row["monthlyCost"]) > 0]
    counts = Counter(row["resourceType"] for row in paid)
    for resource, count in AZURE_COUNTS.items():
        if counts[resource] != count:
            raise ValueError(f"Missing or unexpected Azure pricing coverage: {resource}")
    for row in paid:
        if row["resourceType"] != "azurerm_linux_virtual_machine":
            continue
        if not any(Decimal(item.get("monthlyCost") or "0") > 0 for item in row.get("costComponents", [])):
            raise ValueError("An Azure VM has no priced compute")
        if not row.get("subresources") or not any(
            Decimal(item.get("monthlyCost") or "0") > 0
            for item in row["subresources"]
        ):
            raise ValueError("An Azure VM has no priced OS disk")
    total = Decimal(report["totalMonthlyCost"])
    if not total.is_finite() or total <= 0:
        raise ValueError("Invalid Azure monthly total")
    return total


def load_catalog():
    with urlopen(CATALOG, timeout=30) as response:
        catalog = json.load(response)
    if catalog["locale"]["currencyCode"] != "EUR":
        raise ValueError("Expected an OVH catalog priced in EUR")
    return catalog


def hourly_prices(catalog):
    for group in ("plans", "addons"):
        for product in catalog.get(group, []):
            for price in product.get("pricings", []):
                billing = price.get("intervalUnit"), price.get("interval")
                # Catalog consumption meters (volume, IP, LB) use none/0.
                if billing in {("hour", 1), ("none", 0)} and "consumption" in price.get("capacities", []):
                    yield product["planCode"], price


def ovh_monthly(catalog, selectors):
    if set(selectors) != set(QUANTITIES) or len(set(selectors.values())) != len(QUANTITIES):
        raise ValueError("OVH_STAGING_PRICE_CODES must map all five components to distinct plan codes")
    prices = list(hourly_prices(catalog))
    total = Decimal(0)
    for component, quantity in QUANTITIES.items():
        code = selectors[component]
        rates = {Decimal(row["price"]) / Decimal(100_000_000)
                 for plan, row in prices if plan == code}
        if len(rates) != 1:
            raise ValueError(f"Missing or ambiguous hourly OVH price: {component} ({code})")
        rate = rates.pop()
        if not rate.is_finite() or rate < 0 or (rate == 0 and component != "boot-storage"):
            raise ValueError(f"Non-positive public rate for {component}")
        total += rate * quantity * HOURS
        print(f"OVH {component}: {quantity} × {rate} EUR/h × {HOURS} h")
    return total


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("azure", type=Path, nargs="?")
    parser.add_argument("--list-ovh-codes", action="store_true")
    args = parser.parse_args()
    catalog = load_catalog()
    if args.list_ovh_codes:
        for code, price in sorted(hourly_prices(catalog), key=lambda row: row[0]):
            if re.search(r"c3-4|disk|storage|volume|block|balancer|floating|ipv4|ip-", code, re.I):
                print(code, Decimal(price["price"]) / Decimal(100_000_000))
        return
    if not args.azure:
        parser.error("Specify the Azure Infracost JSON file")
    azure = azure_monthly(args.azure)
    ovh = ovh_monthly(catalog, OVH_CODES)
    winner = "azure" if azure < ovh else "ovh" if ovh < azure else "tie"
    summary = (f"### Staging · tarif public HT\n\n"
               f"Azure **{azure:.2f} EUR/mois** · OVH **{ovh:.2f} EUR/mois**\n\n"
               f"Résultat **{winner}** · 730 h, hors trafic variable, crédits et remises.\n")
    print(summary)
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as file:
        file.write(summary)
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as file:
        print(f"provider={winner}", file=file)


if __name__ == "__main__":
    main()
