"""Promote a checked-out main revision through existing HCP Terraform workspaces."""
import argparse
import json
import os
import re
import subprocess
import time
from urllib.error import HTTPError
from urllib.parse import quote, urlencode, urlsplit
from urllib.request import Request, urlopen

HOST = "https://app.terraform.io"
ORG = "terra_dual_prov"
SUCCESS = {"applied", "planned_and_finished"}
FAILED = {"errored", "canceled", "force_canceled", "discarded", "policy_soft_failed",
          "policy_override", "tf_policy_override", "planned_and_saved"}


def api(path, payload=None, *, optional=False):
    data = None if payload is None else json.dumps(payload).encode()
    request = Request(HOST + "/api/v2" + path, data=data, headers={
        "Authorization": "Bearer " + os.environ["HCP_TERRAFORM_TOKEN"],
        "Content-Type": "application/vnd.api+json",
    })
    try:
        with urlopen(request, timeout=30) as response:
            content = response.read()
            return json.loads(content) if content else None
    except HTTPError as error:
        if optional and error.code == 404:
            return None
        raise RuntimeError(f"HCP API {error.code} for {path}") from None


def workspace(name):
    item = api(f"/organizations/{ORG}/workspaces/{quote(name)}")["data"]
    attrs = item["attributes"]
    env, provider = name.split("-")
    if (attrs["working-directory"] != f"environments/{env}/{provider}"
            or attrs["execution-mode"] != "remote"):
        raise ValueError(f"{name}: unexpected working directory or execution mode")
    vcs = attrs.get("vcs-repo")
    if (not vcs or vcs.get("identifier") != os.environ["GITHUB_REPOSITORY"]
            or vcs.get("branch") not in ("", None, "main")):
        raise ValueError(f"{name}: expected a VCS workspace linked to this repository and main")
    if attrs["auto-apply"] or attrs.get("auto-apply-run-trigger"):
        raise ValueError(f"{name}: disable both auto-apply settings before using this pipeline")
    if attrs.get("auto-destroy-at") or attrs.get("auto-destroy-activity-duration"):
        raise ValueError(f"{name}: disable automatic destruction before using this pipeline")
    return item


def managed_count(name):
    ws = workspace(name)
    state = ws["relationships"]["current-state-version"]["data"]
    if state is None:
        if ws["attributes"]["resource-count"] != 0:
            raise ValueError(f"{name}: inconsistent state metadata")
        return 0
    details = api(f"/state-versions/{state['id']}")["data"]["attributes"]
    url = details["hosted-state-download-url"]
    if urlsplit(url).scheme != "https" or urlsplit(url).hostname != "archivist.terraform.io":
        raise ValueError("Unexpected HCP state download host")
    # State can contain secrets. Read in memory only, never log or upload it.
    try:
        with urlopen(url, timeout=30) as response:
            resources = json.load(response)["resources"]
    except Exception:
        raise RuntimeError(f"{name}: could not read current HCP state") from None
    return sum(len(resource["instances"]) for resource in resources if resource["mode"] == "managed")


def compatible_version(ws):
    env, provider = ws["attributes"]["name"].split("-")
    paths = [f"environments/{env}/{provider}", f"modules/{provider}"]
    revision = os.environ["GITHUB_SHA"]
    for _ in range(12):
        result = api(f"/workspaces/{ws['id']}/configuration-versions?page%5Bsize%5D=20")
        for version in result["data"]:
            attrs = version["attributes"]
            if attrs.get("speculative") or attrs["status"] not in {"uploaded", "archived"}:
                continue
            version_id = version["id"]
            ingress = api(f"/configuration-versions/{version_id}/ingress-attributes", optional=True)
            if not ingress:
                continue
            details = ingress["data"]["attributes"]
            commit = details.get("commit-sha") or ""
            if details.get("is-pull-request") or details.get("branch") != "main":
                continue
            if not re.fullmatch(r"[0-9a-f]{40}", commit):
                continue
            result = subprocess.run(
                ["git", "diff", "--quiet", commit, revision, "--", *paths],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            if result.returncode == 0:
                return version_id
        time.sleep(10)
    raise ValueError(f"{ws['attributes']['name']}: no VCS configuration matches the pipeline revision")


def drain_vcs_plans(ws):
    """Clear VCS plans waiting for approval so the controlled run can proceed."""
    query = urlencode({"filter[status_group]": "non_final"})
    for _ in range(24):
        runs = api(f"/workspaces/{ws['id']}/runs?{query}")["data"]
        if not runs:
            return
        for run in runs:
            attrs = run["attributes"]
            if attrs["source"] not in {"tfe-configuration-version", "tfe-vcs"}:
                raise ValueError(f"Resolve existing run {run['id']} before deploying")
            if attrs["status"] in {"apply_queued", "applying", "confirmed"}:
                raise ValueError(f"Unexpected VCS apply {run['id']}; wait and check state")
            if attrs["actions"]["is-discardable"]:
                api(f"/runs/{run['id']}/actions/discard", {"comment": "Superseded by the deployment pipeline"})
        time.sleep(10)
    raise TimeoutError(f"VCS runs are still queued for {ws['attributes']['name']}")


def execute(ws, version, *, operation, before_apply=None):
    name = ws["attributes"]["name"]
    if operation != "preview":
        drain_vcs_plans(ws)
    run = api("/runs", {"data": {
        "type": "runs",
        "attributes": {
            "message": f"GitHub deployment {os.environ['GITHUB_RUN_ID']} · {name} · {operation}",
            "plan-only": operation == "preview",
            "is-destroy": operation == "destroy",
            "auto-apply": False,
        },
        "relationships": {
            "workspace": {"data": {"type": "workspaces", "id": ws["id"]}},
            "configuration-version": {"data": {"type": "configuration-versions", "id": version}},
        },
    }})["data"]
    run_id = run["id"]
    print(f"{name} / {operation}: {HOST}/app/{ORG}/workspaces/{name}/runs/{run_id}", flush=True)
    approved = False
    for _ in range(180):
        run = api(f"/runs/{run_id}")["data"]
        attrs = run["attributes"]
        status = attrs["status"]
        if status in FAILED:
            raise ValueError(f"{name}: HCP run {run_id} ended with {status}")
        if status in SUCCESS and (operation != "preview" or status == "planned_and_finished"):
            return
        if not approved and attrs["actions"]["is-confirmable"]:
            if operation == "preview":
                raise ValueError(f"{name}: preview unexpectedly permits apply")
            plan_id = run["relationships"]["plan"]["data"]["id"]
            plan = api(f"/plans/{plan_id}")["data"]["attributes"]
            if operation == "deploy" and plan["resource-destructions"] != 0:
                api(f"/runs/{run_id}/actions/discard", {"comment": "Pipeline rejects unexpected deletions"})
                raise ValueError(f"{name}: deployment plan would delete or replace resources")
            if before_apply:
                before_apply()
            api(f"/runs/{run_id}/actions/apply", {"comment": "Approved by the GitHub deployment workflow"})
            approved = True
        time.sleep(10)
    raise TimeoutError(f"{name}: run {run_id} did not finish; check HCP before retrying")


def deploy(env, provider, allow_switch):
    if env == "prod":
        target = workspace("prod-ovh")
        execute(target, compatible_version(target), operation="deploy")
        if not managed_count("prod-ovh"):
            raise ValueError("prod-ovh is still empty after deployment")
        return

    names = {cloud: f"{env}-{cloud}" for cloud in ("azure", "ovh")}
    states = {cloud: managed_count(name) for cloud, name in names.items()}
    if all(states.values()):
        raise ValueError(f"{env}: both providers already have resources; reconcile before deploying")
    if provider == "tie":
        provider = "ovh" if states["ovh"] else "azure"
    other = "ovh" if provider == "azure" else "azure"
    target = workspace(names[provider])
    version = compatible_version(target)
    if states[other]:
        if not allow_switch:
            raise ValueError(f"{names[other]} is active; switching requires allow_switch")
        old = workspace(names[other])
        old_version = compatible_version(old)
        execute(target, version, operation="preview")
        execute(old, old_version, operation="destroy")

    def check_other():
        if managed_count(names[other]):
            raise ValueError(f"{names[other]} still has managed resources")
        # Discard any VCS plans awaiting approval on the inactive side.
        inactive = workspace(names[other])
        drain_vcs_plans(inactive)
        runs = api(f"/workspaces/{inactive['id']}/runs?page%5Bsize%5D=20")["data"]
        for run in runs:
            attrs = run["attributes"]
            if attrs["status"] == "applied":
                break
            if attrs.get("status-timestamps", {}).get("applying-at"):
                raise ValueError(f"{names[other]}: verify orphaned resources after {run['id']}")

    check_other()
    execute(target, version, operation="deploy", before_apply=check_other)
    if not managed_count(names[provider]):
        raise ValueError(f"{names[provider]} is still empty after deployment")
    check_other()


def preflight(include_prod):
    names = ("dev-azure", "dev-ovh", "staging-azure", "staging-ovh")
    if include_prod:
        names += ("prod-ovh",)
    counts = {}
    failures = []
    for name in names:
        try:
            ws = workspace(name)
            counts[name] = managed_count(name)
            compatible_version(ws)
            print(f"{name}: VCS revision verified, {counts[name]} managed resources", flush=True)
        except (KeyError, ValueError, RuntimeError, TimeoutError) as error:
            failures.append(f"{name}: {error}")
    for environment in ("dev", "staging"):
        if all(counts.get(f"{environment}-{cloud}", 0) for cloud in ("azure", "ovh")):
            failures.append(f"{environment}: both providers have resources")
    if failures:
        raise ValueError("HCP preflight failed:\n" + "\n".join(failures))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("environment", choices=("dev", "staging", "prod", "preflight"))
    parser.add_argument("provider", nargs="?", choices=("azure", "ovh", "tie"))
    parser.add_argument("--allow-switch", action="store_true")
    parser.add_argument("--include-prod", action="store_true")
    args = parser.parse_args()
    if os.environ["GITHUB_REF"] != "refs/heads/main":
        parser.error("Deployments must run from main")
    if args.environment == "preflight":
        preflight(args.include_prod)
        return
    if args.provider is None:
        parser.error("Choose a provider for deployment")
    if args.environment == "prod" and args.provider != "ovh":
        parser.error("Production is fixed to OVH")
    deploy(args.environment, args.provider, args.allow_switch)


if __name__ == "__main__":
    main()
