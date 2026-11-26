"""Ingest the UCI Online Retail II dataset into local Parquet files.

Steps
-----
1. Download the official zip from the UCI Machine Learning Repository
   (skipped when the file is already present).
2. Extract the single .xlsx workbook.
3. Stream both worksheets ("Year 2009-2010", "Year 2010-2011") with openpyxl
   and write them, untouched (all text), to data/raw/*.parquet via DuckDB.

No cleaning happens here on purpose: every business rule lives in dbt
(models/staging), where it is versioned, tested and documented.

Dataset: Chen, D. (2012). Online Retail II [Dataset]. UCI Machine Learning
Repository. https://doi.org/10.24432/C5CG6D  -  licensed CC BY 4.0.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import sys
import zipfile
from datetime import datetime
from pathlib import Path

import duckdb
import openpyxl
import requests

DATASET_URL = "https://archive.ics.uci.edu/static/public/502/online+retail+ii.zip"
ROOT = Path(__file__).resolve().parents[1]
RAW_DIR = ROOT / "data" / "raw"
ZIP_PATH = RAW_DIR / "online_retail_ii.zip"

SHEETS = {
    "Year 2009-2010": "online_retail_2009_2010.parquet",
    "Year 2010-2011": "online_retail_2010_2011.parquet",
}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def download(url: str, dest: Path) -> None:
    if dest.exists() and dest.stat().st_size > 0:
        print(f"[ingest] using cached {dest.name}")
        return
    print(f"[ingest] downloading {url}")
    tmp = dest.with_suffix(".part")
    with requests.get(url, stream=True, timeout=120) as r:
        r.raise_for_status()
        with tmp.open("wb") as f:
            for chunk in r.iter_content(chunk_size=1 << 20):
                f.write(chunk)
    tmp.replace(dest)


def extract_xlsx(zip_path: Path, out_dir: Path) -> Path:
    with zipfile.ZipFile(zip_path) as zf:
        members = [m for m in zf.namelist() if m.lower().endswith(".xlsx")]
        if len(members) != 1:
            raise RuntimeError(f"expected one .xlsx in archive, found {members}")
        name = Path(members[0]).name  # never trust paths inside the archive
        target = out_dir / name
        if not target.exists():
            with zf.open(members[0]) as src, target.open("wb") as dst:
                dst.write(src.read())
        return target


def _cell_to_text(value: object) -> str | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.isoformat(sep=" ")
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


def to_parquet(xlsx: Path, force: bool) -> None:
    con = duckdb.connect()
    wb = None
    for sheet, filename in SHEETS.items():
        out = RAW_DIR / filename
        if out.exists() and not force:
            print(f"[ingest] {filename} already exists, skipping")
            continue
        if wb is None:
            print(f"[ingest] opening {xlsx.name} (streaming read, takes a few minutes)")
            wb = openpyxl.load_workbook(xlsx, read_only=True, data_only=True)
        print(f"[ingest] converting sheet '{sheet}' -> {filename}")
        rows = wb[sheet].iter_rows(values_only=True)
        header = [str(h).strip() for h in next(rows)]
        tmp_csv = out.with_suffix(".csv")
        with tmp_csv.open("w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow([*header, "_source_sheet"])
            for row in rows:
                if all(v is None for v in row):
                    continue
                writer.writerow([*(_cell_to_text(v) for v in row), sheet])
        # Every column stays VARCHAR so the raw layer is lossless;
        # typing and cleaning happen in dbt staging.
        con.execute(
            f"""
            COPY (
                SELECT * FROM read_csv('{tmp_csv.as_posix()}', header = true,
                                       all_varchar = true, quote = '"', escape = '"')
            ) TO '{out.as_posix()}' (FORMAT parquet, COMPRESSION zstd)
            """
        )
        tmp_csv.unlink()
        n = con.execute(f"SELECT count(*) FROM '{out.as_posix()}'").fetchone()[0]
        print(f"[ingest]   {n:,} rows")
    if wb is not None:
        wb.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--force", action="store_true", help="rebuild parquet files")
    args = parser.parse_args()

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    download(DATASET_URL, ZIP_PATH)
    print(f"[ingest] sha256 {sha256(ZIP_PATH)}")
    xlsx = extract_xlsx(ZIP_PATH, RAW_DIR)
    to_parquet(xlsx, force=args.force)
    print("[ingest] done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
