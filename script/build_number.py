#!/usr/bin/env python3
"""UTC build identity shared by local packages and CI architectures."""
import argparse
from datetime import datetime, timezone
import os
import re
import xml.etree.ElementTree as ET

FORMAT = "%Y%m%d.%H%M.%S"


def validate(value):
    if not re.fullmatch(r"[0-9]{8}\.[0-9]{4}\.[0-9]{2}", value):
        raise ValueError("build number must use yyyyMMdd.HHmm.ss (UTC)")
    parsed = datetime.strptime(value, FORMAT).replace(tzinfo=timezone.utc)
    if parsed.strftime(FORMAT) != value:
        raise ValueError("invalid UTC build time")
    return value


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("value", nargs="?")
    parser.add_argument("--after", help="previous delivered build number")
    parser.add_argument("--after-feed", help="previous published Sparkle appcast")
    args = parser.parse_args()
    try:
        value = validate(args.value if args.value is not None else
                         os.environ.get("WEIBEI_BUILD_NUMBER", datetime.now(timezone.utc).strftime(FORMAT)))
        if args.after_feed:
            version_key = "{http://www.andymatuschak.org/xml-namespaces/sparkle}version"
            versions = []
            for item in ET.parse(args.after_feed).findall("./channel/item"):
                version = item.findtext(version_key)
                enclosure = item.find("enclosure")
                if version is None and enclosure is not None:
                    version = enclosure.get(version_key)
                versions.append(version)
            if not versions or any(v is None or not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", v) for v in versions):
                raise ValueError("previous appcast has no valid build versions")
            args.after = max(versions, key=lambda v: tuple(map(int, v.split("."))))
        if args.after:
            if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", args.after):
                raise ValueError("invalid previous build number")
            if tuple(map(int, value.split("."))) <= tuple(map(int, args.after.split("."))):
                raise ValueError("build time must be newer than the previous package; check the clock or batch number")
        print(value)
    except (ValueError, OSError, ET.ParseError) as error:
        parser.error(str(error))
