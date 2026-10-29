#!/usr/bin/env python3
"""Exit 0 once a build is live for external TestFlight testers, else 1.

New builds need Apple's beta review before testers on the public link can
install them, which can take a day or two after the GitHub release.

Env: ASC_ISSUER_ID, ASC_KEY_ID, ASC_PRIVATE_KEY (contents of the .p8 file).
Usage: testflight_ready.py <bundle id> <build number>
"""

import sys
import urllib.parse

from next_build_number import get, token


def main() -> None:
    bundle_id, build_number = sys.argv[1], sys.argv[2]
    auth = token()

    apps = get(f"/v1/apps?filter[bundleId]={urllib.parse.quote(bundle_id)}", auth)
    if not apps["data"]:
        sys.exit(f"No App Store Connect app with bundle id {bundle_id}")
    app_id = apps["data"][0]["id"]

    builds = get(
        f"/v1/builds?filter[app]={app_id}"
        f"&filter[version]={urllib.parse.quote(build_number)}"
        "&include=buildBetaDetail"
        "&fields[buildBetaDetails]=externalBuildState",
        auth,
    )
    states = [
        item["attributes"].get("externalBuildState")
        for item in builds.get("included", [])
        if item["type"] == "buildBetaDetails"
    ]

    print(f"Build {build_number}: {states or 'not uploaded yet'}", file=sys.stderr)
    sys.exit(0 if "IN_BETA_TESTING" in states else 1)


if __name__ == "__main__":
    main()
