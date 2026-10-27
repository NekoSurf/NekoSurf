#!/usr/bin/env python3
"""Print the build number Xcode Cloud will assign to its next build run.

Reads the highest Xcode Cloud build run number for the app from the App Store
Connect API and adds one. Also never goes below the build number of the
latest git tag + 1, so a release never reuses a number.

Env: ASC_ISSUER_ID, ASC_KEY_ID, ASC_PRIVATE_KEY (contents of the .p8 file).
Usage: next_build_number.py <bundle id> [min build number]
"""

import json
import os
import sys
import time
import urllib.parse
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"


def token() -> str:
    now = int(time.time())
    return jwt.encode(
        {
            "iss": os.environ["ASC_ISSUER_ID"],
            "iat": now,
            "exp": now + 10 * 60,
            "aud": "appstoreconnect-v1",
        },
        os.environ["ASC_PRIVATE_KEY"],
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def get(url: str, auth: str) -> dict:
    if not url.startswith("http"):
        url = API + url
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {auth}"})
    with urllib.request.urlopen(request) as response:
        return json.load(response)


def main() -> None:
    bundle_id = sys.argv[1]
    floor = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    auth = token()

    apps = get(f"/v1/apps?filter[bundleId]={urllib.parse.quote(bundle_id)}", auth)
    if not apps["data"]:
        sys.exit(f"No App Store Connect app with bundle id {bundle_id}")
    app_id = apps["data"][0]["id"]

    product = get(f"/v1/apps/{app_id}/ciProduct", auth)["data"]

    highest = 0
    url = f"/v1/ciProducts/{product['id']}/buildRuns?limit=200&fields[ciBuildRuns]=number"
    while url:
        page = get(url, auth)
        for run in page["data"]:
            highest = max(highest, run["attributes"].get("number") or 0)
        url = page.get("links", {}).get("next")

    print(f"Highest Xcode Cloud build run: {highest}", file=sys.stderr)
    print(max(highest + 1, floor))


if __name__ == "__main__":
    main()
