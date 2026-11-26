# Data attribution

This project uses the **Online Retail II** dataset:

> Chen, D. (2012). *Online Retail II* [Dataset]. UCI Machine Learning Repository.
> https://doi.org/10.24432/C5CG6D

- Source: https://archive.ics.uci.edu/dataset/502/online+retail+ii
- License: [Creative Commons Attribution 4.0 International (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/)
- Content: all transactions of a UK-based, registered non-store online retailer
  of giftware between 1 Dec 2009 and 9 Dec 2011.

## What we changed

The raw workbook is **not** redistributed in this repository; `scripts/ingest.py`
downloads it from UCI at build time. The pipeline removes overlapping and
duplicate rows, classifies lines (sale / cancellation / adjustment / non-product),
and aggregates them. The only data committed here (`dashboard/data/*.json`) are
aggregates derived from the dataset: monthly and weekly totals, country, product
and segment summaries, and cohort counts. No customer identifiers or invoice
lines are published.

The customer and retailer in the dataset are not clients of Tabi Digital
Solutions; this is an internal engineering demonstration on public data.
