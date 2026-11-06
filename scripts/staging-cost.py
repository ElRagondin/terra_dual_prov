"""Compare the hourly-list-price baseline for the deployed staging topology."""
import argparse
from hashlib import sha256
from collections import Counter
from decimal import Decimal
import json
import os
from pathlib import Path
import re
import time
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import urlopen

CATALOG = "https://eu.api.ovh.com/1.0/order/catalog/public/cloud?ovhSubsidiary=FR"
HOURS = Decimal(730)
AZURE_RETAIL = "https://prices.azure.com/api/retail/prices"
MODEL_FINGERPRINTS = {
    "azure": "483ea1f7634f713fe2444b7f672b7d5c80c2ba149e3af12c09e190cd941b2963",
    "ovh": "5c1d73dac7729b688d15b8a089368bf6e21878015405df3a656fa0fba146de01",
}
LB_METER = "Standard Included LB Rules and Outbound Rules"
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
    "azurerm_public_ip": 1,
}


def fingerprint(cloud):
    root = Path(f"environments/staging/{cloud}")
    modules = Path(f"modules/{cloud}")
    paths = sorted([*root.glob("*.tf"), *root.glob("*.tfvars"), *modules.rglob("*.tf")])
    text = "".join(f"{path.as_posix()}\0{path.read_text(encoding='utf-8').rstrip()}\0"
                   for path in paths if ".terraform" not in path.parts)
    return sha256(text.encode()).hexdigest()


def retail_prices(clause):
    url = AZURE_RETAIL + "?" + urlencode({
        "currencyCode": "'EUR'",
        "$filter": f"priceType eq 'Consumption' and ({clause})",
    })
    for attempt in range(4):
        try:
            with urlopen(url, timeout=20) as response:
                page = json.load(response, parse_float=Decimal)
            break
        except HTTPError as error:
            if error.code not in {429, 502, 503, 504} or attempt == 3:
                raise
            time.sleep(2 ** (attempt + 1))
    if page.get("NextPageLink"):
        raise ValueError("Azure retail query is not specific enough")
    return page["Items"]


def retail_rate(rows, **match):
    rates = {Decimal(row["retailPrice"]) for row in rows
             if row["type"] == "Consumption" and row["currencyCode"] == "EUR"
             and row["tierMinimumUnits"] == 0
             and all(row.get(key) == value for key, value in match.items())}
    if len(rates) != 1:
        raise ValueError(f"Missing or ambiguous Azure retail rate for {match}")
    rate = rates.pop()
    if not rate.is_finite() or rate <= 0:
        raise ValueError(f"Invalid Azure retail rate for {match}")
    return rate


def azure_lb_monthly():
    rows = retail_prices(f"serviceName eq 'Load Balancer' and meterName eq '{LB_METER}'")
    rate = retail_rate(rows, armRegionName="Global", productName="Load Balancer",
                       skuName="Standard", meterName=LB_METER, unitOfMeasure="1 Hour")
    return rate * HOURS


def azure_retail_monthly(lb):
    region = "armRegionName eq 'spaincentral'"
    compute = retail_prices(f"{region} and armSkuName eq 'Standard_B2ats_v2'")
    disks = retail_prices(f"{region} and serviceName eq 'Storage' and "
                          "(skuName eq 'P6 LRS' or skuName eq 'E3 LRS')")
    ips = retail_prices(f"{region} and meterName eq 'Standard IPv4 Static Public IP'")
    vm = retail_rate(compute, productName="Virtual Machines Basv2 Series",
                     meterName="B2ats v2", unitOfMeasure="1 Hour")
    os_disk = retail_rate(disks, productName="Premium SSD Managed Disks",
                          meterName="P6 LRS Disk", unitOfMeasure="1/Month")
    data_disk = retail_rate(disks, productName="Standard SSD Managed Disks",
                            meterName="E3 LRS Disk", unitOfMeasure="1/Month")
    ip = retail_rate(ips, productName="IP Addresses", skuName="Standard",
                     unitOfMeasure="1 Hour")
    return (3 * vm + ip) * HOURS + 3 * os_disk + data_disk + lb


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
    # Standard Regional LB bills the first five rules once. Replace the
    # Infracost rule overage estimates with that bundle in main().
    total = Decimal(report["totalMonthlyCost"]) - sum(
        Decimal(row["monthlyCost"]) for row in paid
        if row["resourceType"] in {"azurerm_lb", "azurerm_lb_rule"}
    )
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
    parser.add_argument("--show-fingerprints", action="store_true")
    args = parser.parse_args()
    if args.show_fingerprints:
        for cloud in MODEL_FINGERPRINTS:
            print(cloud, fingerprint(cloud))
        return
    catalog = load_catalog()
    if args.list_ovh_codes:
        for code, price in sorted(hourly_prices(catalog), key=lambda row: row[0]):
            if re.search(r"c3-4|disk|storage|volume|block|balancer|floating|ipv4|ip-", code, re.I):
                print(code, Decimal(price["price"]) / Decimal(100_000_000))
        return
    for cloud, expected in MODEL_FINGERPRINTS.items():
        if fingerprint(cloud) != expected:
            raise ValueError(f"Review the staging {cloud} cost model after Terraform changes")
    lb = azure_lb_monthly()
    if args.azure:
        azure = azure_monthly(args.azure) + lb
        source = "Infracost + tarif public du load balancer"
    else:
        azure = azure_retail_monthly(lb)
        source = "Azure Retail Prices API"
    ovh = ovh_monthly(catalog, OVH_CODES)
    winner = "azure" if azure < ovh else "ovh" if ovh < azure else "tie"
    summary = (f"### Staging · tarif public HT\n\n"
               f"Azure **{azure:.2f} EUR/mois** ({source}) · OVH **{ovh:.2f} EUR/mois**\n\n"
               f"Résultat **{winner}** · 730 h, hors trafic variable, crédits et remises.\n")
    print(summary)
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as file:
        file.write(summary)
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as file:
        print(f"provider={winner}", file=file)


if __name__ == "__main__":
    main()
