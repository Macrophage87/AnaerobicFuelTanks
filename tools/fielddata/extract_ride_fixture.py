#!/usr/bin/env python3
"""Turn one saved DualTank ride (.fit) into the committed text fixtures that the
field-data ritual requires (docs/agents/rituals/FIELD_DATA.md).

WHY THIS EXISTS. A recording is not evidence until something committed can
regenerate every figure taken from it. No .fit is ever committed here (the
repository is public and a .fit carries GPS and heart rate), so this script is
the documented, re-runnable bridge: anyone holding the original file runs it and
must get byte-identical fixtures. Every figure published from the ride is then
derived from those fixtures by tools/fielddata/ride_evidence.py, which runs in CI.

WHAT IS KEPT, AND WHAT IS DROPPED ON PURPOSE.
  kept:    seconds since the first record, native power, and this app's two
           developer fields (PCr_J, GLY_J); timer start/stop events as seconds;
           the structural inventory of every developer field in the file
           (names, types, units, target message) -- not their values.
  dropped: GPS, heart rate, HRV, cadence, speed, distance, absolute timestamps,
           serial numbers, and every other app's values. None of them is needed
           by any figure this repository publishes from the ride.

WHICH DEVELOPER FIELDS ARE "OURS". Matched by field_description NAME (PCr_J,
GLY_J) within one developer_data_index, never by application id: in the first
ride decoded (i188577527) the application id carried in the file is NOT the
manifest id in connectiq/manifest.xml. The extractor records both so a reader
can see the difference; it refuses a file where the two names sit under
different indices or appear under more than one.

Usage:
  python3 tools/fielddata/extract_ride_fixture.py <ride.fit> <label>
writes tools/fielddata/fixtures/<label>.series.csv, .events.csv and .inventory.txt.

Requires fitparse (pip install fitparse==1.2.0). Not run in CI: CI has no .fit.
"""

import argparse
import os
import sys

MANIFEST_APP_ID = "fc13e61e7ca54c998c7a7c64f0ef4434"
OURS = ("PCr_J", "GLY_J")
TYPE_BYTES = {"float32": 4, "uint16": 2, "sint16": 2, "uint8": 1, "sint8": 1,
              "uint32": 4, "sint32": 4, "float64": 8, "uint8z": 1, "uint16z": 2,
              "uint32z": 4, "string": 1, "byte": 1, "enum": 1}


def f32(x):
    """float32 values written with 9 significant digits: exact round-trip."""
    return "" if x is None else "%.9g" % x


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("fit")
    ap.add_argument("label")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                  "fixtures"))
    a = ap.parse_args()
    import fitparse  # imported here so --help works without it

    ff = fitparse.FitFile(a.fit, check_crc=True)
    dev_app, fdesc, records, events = {}, [], [], []
    file_id, creator = {}, {}
    for m in ff.get_messages():
        if m.name == "file_id":
            file_id = {f.name: f.value for f in m.fields}
        elif m.name == "device_info":
            v = {f.name: f.value for f in m.fields}
            if v.get("device_index") == "creator" and not creator:
                creator = v
        elif m.name == "developer_data_id":
            v = {f.name: f.value for f in m.fields}
            app = v.get("application_id")
            dev_app[v.get("developer_data_index")] = bytes(app).hex() if app is not None else ""
        elif m.name == "field_description":
            v = {f.name: f.value for f in m.fields}
            fdesc.append((v.get("developer_data_index"), v.get("field_definition_number"),
                          v.get("field_name"), v.get("fit_base_type_id"), v.get("units"),
                          v.get("native_mesg_num")))
        elif m.name == "event":
            v = {f.name: f.value for f in m.fields}
            if v.get("event") == "timer":
                events.append((v.get("timestamp"), v.get("event_type")))
        elif m.name == "record":
            row = {"ts": None, "power": None, "PCr_J": None, "GLY_J": None, "idx": {}}
            for f in m.fields:
                if f.name == "timestamp":
                    row["ts"] = f.value
                elif f.name == "power":
                    row["power"] = f.value
                fd = getattr(f, "field_def", None)
                if fd is not None and hasattr(fd, "dev_data_index") and f.name in OURS:
                    row[f.name] = f.value
                    row["idx"][f.name] = fd.dev_data_index
            records.append(row)

    ours = [d for d in fdesc if d[2] in OURS]
    idxs = {d[0] for d in ours}
    if sorted(d[2] for d in ours) != sorted(OURS) or len(idxs) != 1:
        sys.exit("REFUSED: expected exactly one PCr_J and one GLY_J field_description under one "
                 "developer_data_index; found %r" % (ours,))
    our_idx = idxs.pop()
    if not records:
        sys.exit("REFUSED: no record messages")

    t0 = records[0]["ts"]
    rel = lambda t: int(round((t - t0).total_seconds()))
    os.makedirs(a.out, exist_ok=True)
    base = os.path.join(a.out, a.label)
    fw = creator.get("software_version")

    head = [
        "# PROVENANCE -- reproducible from the original with tools/fielddata/extract_ride_fixture.py",
        "#   source file    %s (not committed: carries GPS and heart rate)" % os.path.basename(a.fit),
        "#   device         garmin_product %s, firmware %s; recorded on %s (date only: the start"
        % (file_id.get("garmin_product"), fw, file_id.get("time_created").date()
           if file_id.get("time_created") else "?"),
        "#                  time is dropped so relative seconds cannot be turned into clock times)",
        "#   ours           developer_data_index %d, application_id %s (manifest id is %s)"
        % (our_idx, dev_app.get(our_idx, ""), MANIFEST_APP_ID),
        "#   CRC            verified by fitparse check_crc=True",
    ]

    with open(base + ".series.csv", "w", newline="\n") as fh:
        for h in head:
            fh.write(h + "\n")
        fh.write("#   values         record messages (FIT global 20) in file order; t = seconds since the\n"
                 "#                  first record; power = native field 7 (W); PCr_J / GLY_J = this app's\n"
                 "#                  developer fields 0 / 1, float32, written with 9 significant digits\n"
                 "#                  (exact round-trip)\n"
                 "#   absence        an EMPTY cell means the field was absent from that record; 0 W is a\n"
                 "#                  real power reading. Record fields latch (FACTS.md 3.3), so a repeated\n"
                 "#                  value can be a steady state or a re-emitted one.\n"
                 "#   columns        read BY NAME; a loader must refuse a row whose cell count differs\n"
                 "#                  from the header's.\n"
                 "#   cross-checks   records %d; first PCr_J %s, GLY_J %s; last t %d\n"
                 % (len(records), f32(records[0]["PCr_J"]), f32(records[0]["GLY_J"]),
                    rel(records[-1]["ts"])))
        fh.write("t,power,PCr_J,GLY_J\n")
        for r in records:
            fh.write("%d,%s,%s,%s\n" % (rel(r["ts"]), "" if r["power"] is None else r["power"],
                                        f32(r["PCr_J"]), f32(r["GLY_J"])))

    with open(base + ".events.csv", "w", newline="\n") as fh:
        for h in head:
            fh.write(h + "\n")
        fh.write("#   values         timer event messages (FIT global 21, event=timer) in file order;\n"
                 "#                  t = seconds since the first record (may be negative)\n"
                 "#   cross-checks   %d timer events\n" % len(events))
        fh.write("t,event_type\n")
        for t, e in events:
            fh.write("%d,%s\n" % (rel(t), e))

    with open(base + ".inventory.txt", "w", newline="\n") as fh:
        for h in head:
            fh.write(h + "\n")
        fh.write("#   values         every developer field_description in the file: index, field number,\n"
                 "#                  name, FIT base type, units, target message. Values of other apps'\n"
                 "#                  fields are NOT recorded here; only that they were declared.\n"
                 "#   bytes          one element of the base type (arrays counted once)\n")
        fh.write("index\tfield\tname\ttype\tbytes\tunits\tmesg\tours\n")
        for d in sorted(fdesc, key=lambda d: (d[0], d[5] or "", d[1])):
            units = (d[4] or "").encode("ascii", "replace").decode("ascii")
            fh.write("%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" % (
                d[0], d[1], d[2], d[3], TYPE_BYTES.get(d[3], "?"), units, d[5],
                "yes" if d[0] == our_idx and d[2] in OURS else ""))
    print("wrote %s.{series.csv,events.csv,inventory.txt}: %d records, %d timer events, %d field "
          "descriptions, ours at index %d" % (base, len(records), len(events), len(fdesc), our_idx))


if __name__ == "__main__":
    main()
