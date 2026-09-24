#!/usr/bin/env python3
"""Build the compact iOS AUSNUT 2023 nutrition resource from FSANZ workbooks."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd


def number(value, digits=3):
    if pd.isna(value):
        return None
    return round(float(value), digits)


def text(value):
    if pd.isna(value):
        return None
    cleaned = " ".join(str(value).split())
    return cleaned or None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--details", required=True, type=Path)
    parser.add_argument("--nutrients", required=True, type=Path)
    parser.add_argument("--measures", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    details = pd.read_excel(args.details, sheet_name="Food details", header=2)
    nutrients = pd.read_excel(args.nutrients, sheet_name="Food nutrient profiles", header=2)
    measures = pd.read_excel(args.measures, sheet_name="AUSNUT 2023", header=2)

    details = details[pd.to_numeric(details["Survey ID"], errors="coerce").notna()].copy()
    details["Survey ID"] = details["Survey ID"].astype(str)
    nutrients["Survey ID"] = nutrients["Survey ID"].astype(str)
    measures["Survey ID"] = measures["Survey ID"].astype(str)

    details_by_id = details.set_index("Survey ID").to_dict("index")
    measures_by_id = {}
    for survey_id, group in measures.groupby("Survey ID"):
        options = []
        seen = set()
        for _, row in group.iterrows():
            descriptor_parts = [text(row.get(column)) for column in ["Descriptor 1\n", "Descriptor 2", "Descriptor 3", "Descriptor 4\n"]]
            descriptor = " ".join(part for part in descriptor_parts if part)
            grams = number(row.get("Gram amount"), 2)
            quantity = number(row.get("Quantity"), 2) or 1
            if not descriptor or descriptor.lower().startswith("density") or not grams or grams <= 0:
                continue
            key = (descriptor.lower(), quantity, grams)
            if key in seen:
                continue
            seen.add(key)
            options.append({"n": descriptor, "q": quantity, "g": grams})
        measures_by_id[survey_id] = options[:8]

    records = []
    for _, row in nutrients.iterrows():
        survey_id = str(row["Survey ID"])
        detail = details_by_id.get(survey_id, {})
        energy_kj = number(row.get("Energy with dietary fibre (kJ)"), 2) or 0
        record = {
            "id": survey_id,
            "key": text(row.get("Public food key")),
            "name": text(row.get("Food name")),
            "description": text(detail.get("Food description")),
            "derivation": text(row.get("Derivation")),
            "kcal": round(energy_kj / 4.184, 2),
            "protein": number(row.get("Protein (g)")),
            "carbs": number(row.get("Available carbohydrate, with sugar alcohols (g)")),
            "fat": number(row.get("Total fat (g)")),
            "sugar": number(row.get("Total sugars (g)")),
            "addedSugar": number(row.get("Added sugars (g)")),
            "fiber": number(row.get("Dietary fibre (g)")),
            "saturatedFat": number(row.get("Total saturated fat (g)")),
            "monounsaturatedFat": number(row.get("Total monounsaturated fat (g)")),
            "polyunsaturatedFat": number(row.get("Total polyunsaturated fat (g)")),
            "transFatMg": number(row.get("Total trans fatty acids (mg)")),
            "cholesterol": number(row.get("Cholesterol (mg)")),
            "caffeine": number(row.get("Caffeine (mg)")),
            "sodium": number(row.get("Sodium (Na) (mg)")),
            "potassium": number(row.get("Potassium (K) (mg)")),
            "calcium": number(row.get("Calcium (Ca) (mg)")),
            "iron": number(row.get("Iron (Fe) (mg)")),
            "magnesium": number(row.get("Magnesium (Mg) (mg)")),
            "zinc": number(row.get("Zinc (Zn) (mg)")),
            "vitaminA": number(row.get("Vitamin A retinol equivalents (ug)")),
            "vitaminC": number(row.get("Vitamin C (mg)")),
            "vitaminD": number(row.get("Vitamin D3 equivalents (ug)")),
            "vitaminB12": number(row.get("Cobalamin (B12) (ug)")),
            "vitaminE": number(row.get("Vitamin E (mg)")),
            "folate": number(row.get("Dietary folate equivalents (ug)")),
            "omega3Mg": number(row.get("Total long chain omega 3 fatty acids (mg)")),
            "measures": measures_by_id.get(survey_id, []),
        }
        records.append({key: value for key, value in record.items() if value is not None and value != []})

    payload = {
        "source": "Food Standards Australia New Zealand, AUSNUT 2023",
        "release": "2023",
        "basis": "per 100 g edible portion",
        "foods": records,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"Wrote {len(records)} foods to {args.output} ({args.output.stat().st_size / 1024 / 1024:.2f} MB)")


if __name__ == "__main__":
    main()
