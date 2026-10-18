#!/usr/bin/env python3
import json
import os


EXPECTED = {
    "vcluster-pro": {
        "image": "ghcr.io/loft-sh/vcluster-pro:v0.38.0-rc.1",
        "critical": 1,
        "high": 2,
        "medium": 3,
        "low": 4,
        "status": "completed",
    },
    "vcluster-oss": {
        "image": "ghcr.io/loft-sh/vcluster-oss:v0.38.0-rc.1",
        "critical": 0,
        "high": 1,
        "medium": 2,
        "low": 3,
        "status": "completed",
    },
    "vcluster-cli": {
        "image": "ghcr.io/loft-sh/vcluster-cli:v0.38.0-rc.1",
        "critical": 0,
        "high": 0,
        "medium": 1,
        "low": 2,
        "status": "completed",
    },
}


def main():
    outputs = json.loads(os.environ["SCAN_RESULTS"])
    assert set(outputs) == set(EXPECTED), outputs

    for output_name, expected in EXPECTED.items():
        actual = json.loads(outputs[output_name])
        assert actual == expected, {"output": output_name, "actual": actual}

    print("All uniquely named matrix outputs reached the fan-in job.")


if __name__ == "__main__":
    main()
