#!/usr/bin/env python3
"""Read-only audit of assets/data/questions.json. Does not modify any files."""
import json
import re
import collections
from pathlib import Path

PATH = Path(__file__).resolve().parent.parent / "assets" / "data" / "questions.json"
REQUIRED = ["id", "category", "subcategory", "difficulty", "question", "options", "correctIndex"]
MOJIBAKE = re.compile(
    r"â€™|â€œ|â€|â€¦|Ã.|Â.|ï¿½|\uFFFD|â€˜|â€”"
)


def norm_text(t: str) -> str:
    t = t.lower()
    t = re.sub(r"[^\w\s]", " ", t)
    return re.sub(r"\s+", " ", t).strip()


def main():
    data = json.loads(PATH.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise SystemExit("Expected top-level JSON array")

    questions = data
    total = len(questions)

    report = {
        "total": total,
        "categories": {},
        "dup_ids": {},
        "exact_dup": {},
        "near_dup": {},
        "ci_dist_overall": {},
        "ci_dist_by_cat": {},
        "ci_invalid": [],
        "dup_options": [],
        "empty_fields": [],
        "malformed": [],
        "bad_option_count": [],
        "encoding": [],
        "ambiguous": [],
        "manual_checks": [],
    }

    # Categories
    cat_counts = collections.Counter(q.get("category") for q in questions)
    report["categories"] = dict(sorted(cat_counts.items(), key=lambda x: (-x[1], x[0])))

    # Duplicate IDs
    id_to_indices = collections.defaultdict(list)
    for i, q in enumerate(questions):
        id_to_indices[q.get("id")].append(i)
    for k, indices in id_to_indices.items():
        if len(indices) > 1:
            report["dup_ids"][k] = [questions[i].get("id") for i in indices]

    # correctIndex overall and per category
    ci_overall = collections.Counter()
    ci_by_cat = collections.defaultdict(collections.Counter)
    for q in questions:
        ci = q.get("correctIndex")
        cat = q.get("category", "UNKNOWN")
        if ci is None:
            ci_overall["null/missing"] += 1
            ci_by_cat[cat]["null/missing"] += 1
            report["ci_invalid"].append(
                {"id": q.get("id"), "correctIndex": ci, "reason": "missing"}
            )
        elif not isinstance(ci, int) or isinstance(ci, bool):
            ci_overall["non-int"] += 1
            ci_by_cat[cat]["non-int"] += 1
            report["ci_invalid"].append(
                {"id": q.get("id"), "correctIndex": ci, "reason": "non-int"}
            )
        elif ci < 0 or ci > 3:
            ci_overall["out-of-range"] += 1
            ci_by_cat[cat]["out-of-range"] += 1
            report["ci_invalid"].append(
                {"id": q.get("id"), "correctIndex": ci, "reason": "out-of-range"}
            )
        else:
            ci_overall[ci] += 1
            ci_by_cat[cat][ci] += 1

    report["ci_dist_overall"] = {str(k): v for k, v in sorted(ci_overall.items(), key=lambda x: str(x[0]))}
    report["ci_dist_by_cat"] = {
        cat: {str(k): v for k, v in sorted(cnt.items(), key=lambda x: str(x[0]))}
        for cat, cnt in sorted(ci_by_cat.items())
    }

    # Structural issues
    for q in questions:
        qid = q.get("id")
        issues = []

        for f in REQUIRED:
            if f not in q:
                issues.append(f"missing:{f}")
                report["empty_fields"].append({"id": qid, "field": f, "issue": "missing"})
            elif q[f] is None:
                issues.append(f"null:{f}")
                report["empty_fields"].append({"id": qid, "field": f, "issue": "null"})
            elif f in (
                "id",
                "category",
                "subcategory",
                "difficulty",
                "question",
            ) and isinstance(q[f], str) and not str(q[f]).strip():
                issues.append(f"empty:{f}")
                report["empty_fields"].append({"id": qid, "field": f, "issue": "empty"})

        opts = q.get("options")
        if not isinstance(opts, list):
            issues.append("options-not-array")
            report["bad_option_count"].append(
                {"id": qid, "detail": type(opts).__name__, "options": opts}
            )
        elif len(opts) != 4:
            issues.append(f"options-len-{len(opts)}")
            report["bad_option_count"].append(
                {"id": qid, "detail": len(opts), "options": opts}
            )
        else:
            for i, o in enumerate(opts):
                if o is None or (isinstance(o, str) and not str(o).strip()):
                    issues.append(f"empty-option-{i}")
                    report["empty_fields"].append(
                        {"id": qid, "field": f"options[{i}]", "issue": "empty"}
                    )
            norms = [str(o).strip().lower() for o in opts]
            if len(norms) != len(set(norms)):
                issues.append("duplicate-options")
                report["dup_options"].append({"id": qid, "options": opts})

        if issues:
            report["malformed"].append({"id": qid, "issues": issues})

    # Encoding
    for q in questions:
        blob = json.dumps(q, ensure_ascii=False)
        if MOJIBAKE.search(blob):
            m = list(set(MOJIBAKE.findall(blob)))
            report["encoding"].append(
                {
                    "id": q.get("id"),
                    "patterns": m,
                    "question": str(q.get("question", ""))[:120],
                }
            )

    # Exact duplicate question text
    exact_map = collections.defaultdict(list)
    for q in questions:
        t = str(q.get("question", "")).strip().lower()
        if t:
            exact_map[t].append(q.get("id"))
    for t, ids in exact_map.items():
        if len(ids) > 1:
            report["exact_dup"][t] = ids

    # Near duplicate
    near_map = collections.defaultdict(list)
    for q in questions:
        t = norm_text(str(q.get("question", "")))
        if t:
            near_map[t].append(
                {"id": q.get("id"), "question": str(q.get("question", ""))[:100]}
            )
    for t, items in near_map.items():
        if len(items) > 1:
            report["near_dup"][t] = items

    # Ambiguous / manual checks
    manual_ids = {"rea_001", "pol_108", "sgk_001"}

    for q in questions:
        qid = q.get("id")
        reasons = []
        text = str(q.get("question", ""))
        tl = text.lower()
        opts = q.get("options") or []
        cat = q.get("category", "")
        sub = str(q.get("subcategory", ""))
        ci = q.get("correctIndex")

        if qid in manual_ids:
            reasons.append("manual-review-requested")

        if re.search(
            r"all of the above|none of the above|both a and b|both of the above",
            tl,
            re.I,
        ) or any(
            re.search(
                r"all of the above|none of the above|both a and b",
                str(o),
                re.I,
            )
            for o in opts
        ):
            reasons.append("meta-option")

        if cat == "Current Affairs":
            reasons.append("current-affairs-staleness")

        if cat in ("Math", "Reasoning") or "number series" in sub.lower():
            if re.search(
                r"next term|find the next|smallest number|largest number|remainder|percentage change|net percentage",
                tl,
            ):
                reasons.append("math-reasoning-verify")

        if "president" in tl and "parliament" in tl and "submit" in tl:
            reasons.append("factual-debate")

        if isinstance(opts, list) and isinstance(ci, int) and 0 <= ci < len(opts):
            ans = str(opts[ci]).strip().lower()
            if ans and len(ans) > 4 and ans in tl:
                reasons.append("answer-visible-in-stem")

        if len(text.strip()) < 25:
            reasons.append("very-short-stem")

        if qid == "rea_001":
            # Pattern: 4,6,12,36,144 -> multipliers 1.5,2,3,4 -> next *5 = 720 (index 1)
            if ci == 2:
                reasons.append("likely-wrong-correctIndex-expected-720-at-index-1")

        if qid == "pol_108":
            reasons.append("cag-reporting-debate-all-of-above")

        if qid == "sgk_001":
            reasons.append("election-dispute-body-debate")

        if reasons:
            report["ambiguous"].append(
                {
                    "id": qid,
                    "category": cat,
                    "reasons": reasons,
                    "question": text[:120],
                    "correctIndex": ci,
                    "markedAnswer": opts[ci] if isinstance(opts, list) and isinstance(ci, int) and 0 <= ci < len(opts) else None,
                }
            )

    # Manual check details
    for qid in manual_ids:
        q = next((x for x in questions if x.get("id") == qid), None)
        if q:
            report["manual_checks"].append(
                {
                    "id": qid,
                    "question": q.get("question"),
                    "options": q.get("options"),
                    "correctIndex": q.get("correctIndex"),
                    "markedAnswer": q["options"][q["correctIndex"]]
                    if isinstance(q.get("options"), list)
                    and isinstance(q.get("correctIndex"), int)
                    and 0 <= q["correctIndex"] < len(q["options"])
                    else None,
                }
            )

    import sys

    if "--json" in sys.argv:
        print(json.dumps(report, indent=2, ensure_ascii=False))
        return

    # Human-readable summary (default)
    def pct(n):
        return f"{100.0 * n / total:.1f}%" if total else "0%"

    print("=" * 72)
    print("QUESTIONS.JSON AUDIT SUMMARY (read-only)")
    print("=" * 72)
    print(f"Total questions: {total}")
    print("\n--- Category counts ---")
    for c, n in sorted(report["categories"].items(), key=lambda x: (-x[1], x[0])):
        print(f"  {c}: {n}")

    dup = report["dup_ids"]
    print(f"\n--- Duplicate IDs: {len(dup)} id values, {sum(len(v) - 1 for v in dup.values())} extra rows ---")
    for k, v in sorted(dup.items(), key=lambda x: -len(x[1])):
        print(f"  {k}: appears {len(v)} times")

    print("\n--- correctIndex (overall) ---")
    for k in ("0", "1", "2", "3", "null/missing", "non-int", "out-of-range"):
        if k in report["ci_dist_overall"] or k in [str(x) for x in range(4)]:
            pass
    for k, v in sorted(report["ci_dist_overall"].items(), key=lambda x: x[0]):
        print(f"  {k}: {v} ({pct(v)})")

    print("\n--- correctIndex by category ---")
    for cat, dist in sorted(report["ci_dist_by_cat"].items()):
        parts = ", ".join(f"{k}={v}" for k, v in sorted(dist.items(), key=lambda x: x[0]))
        print(f"  {cat}: {parts}")

    print(f"\n--- Invalid correctIndex: {len(report['ci_invalid'])} ---")
    for row in report["ci_invalid"]:
        print(f"  {row['id']}: {row['correctIndex']} ({row['reason']})")

    print(f"\n--- Options count != 4: {len(report['bad_option_count'])} ---")
    for row in report["bad_option_count"]:
        print(f"  {row['id']}: {row['detail']}")

    print(f"\n--- Duplicate options within question: {len(report['dup_options'])} ---")
    for row in report["dup_options"]:
        print(f"  {row['id']}: {row['options']}")

    print(f"\n--- Empty/missing fields: {len(report['empty_fields'])} ---")
    for row in report["empty_fields"][:50]:
        print(f"  {row['id']}: {row['field']} ({row['issue']})")
    if len(report["empty_fields"]) > 50:
        print(f"  ... and {len(report['empty_fields']) - 50} more")

    print(f"\n--- Malformed (any structural issue): {len(report['malformed'])} ---")
    for row in report["malformed"][:50]:
        print(f"  {row['id']}: {', '.join(row['issues'])}")
    if len(report["malformed"]) > 50:
        print(f"  ... and {len(report['malformed']) - 50} more")

    print(f"\n--- Encoding/mojibake: {len(report['encoding'])} ---")
    for row in report["encoding"][:30]:
        print(f"  {row['id']}: {row['patterns']}")

    exact = report["exact_dup"]
    print(f"\n--- Exact duplicate question text: {len(exact)} groups, {sum(len(v) - 1 for v in exact.values())} redundant ---")
    for t, ids in sorted(exact.items(), key=lambda x: -len(x[1])):
        print(f"  [{len(ids)}] {ids}")
        print(f"      {t[:100]}")

    near = report["near_dup"]
    print(f"\n--- Near-duplicate (normalized): {len(near)} groups, {sum(len(v) - 1 for v in near.values())} redundant ---")
    for t, items in sorted(near.items(), key=lambda x: -len(x[1]))[:60]:
        ids = [i["id"] for i in items]
        print(f"  [{len(ids)}] {ids}")
        print(f"      norm: {t[:80]}")
        for i in items:
            print(f"        {i['id']}: {i['question']}")

    if len(near) > 60:
        print(f"  ... and {len(near) - 60} more groups")

    print(f"\n--- Ambiguous / review flagged: {len(report['ambiguous'])} ---")
    for row in sorted(report["ambiguous"], key=lambda x: -len(x["reasons"])):
        print(f"  {row['id']} ({row['category']}): {', '.join(row['reasons'])}")
        print(f"      Q: {row['question']}")
        print(f"      marked [{row['correctIndex']}]: {row['markedAnswer']}")

    print("\n--- Manual checks (requested) ---")
    for row in report["manual_checks"]:
        print(f"  {row['id']}:")
        print(f"    Q: {row['question']}")
        print(f"    options: {row['options']}")
        print(f"    correctIndex={row['correctIndex']} -> {row['markedAnswer']}")

    print("=" * 72)


if __name__ == "__main__":
    main()
