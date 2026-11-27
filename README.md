# Frequent Itemset Mining Using Eclat (Julia)

[![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/24127226/16-FIM-DATA-MINING/blob/main/notebooks/demo.ipynb)

Course project for **CSC14004 -- Data Mining and Applications** (Class `24KHMT1`, Semester 1, Academic Year 2026--2027), Faculty of Information Technology, University of Science, VNU-HCM.

This repository provides a from-scratch Julia implementation of the **Eclat** algorithm for frequent itemset mining based on the vertical tidset representation and prefix-based equivalence class decomposition introduced in the original paper:

> M. J. Zaki, "Scalable Algorithms for Association Mining," *IEEE Transactions on Knowledge and Data Engineering*, vol. 12, no. 3, pp. 372--390, 2000. [PDF](https://www.cs.rpi.edu/~zaki/PaperDir/TKDE00.pdf)

---

## Team Members

| Full Name | Student ID | Primary Responsibilities |
|---|---|---|
| Phạm Trần Anh Quân | `24127226` | Core Eclat algorithm, performance optimizations, complexity analysis, and Application 2 (BoVW) |
| Nguyễn Tiến Cường | `24127337` | SPMF I/O & CLI, automated verification & CI, benchmarking infrastructure, Application 1 (Groceries), Colab notebook, and documentation |

- **Lecturer:** Prof. Lê Hoài Bắc
- **Lab Instructor:** M.Sc. Huỳnh Lâm Hải Đăng
- **Teaching Assistant:** M.Sc. Nguyễn Ngọc Đức

---

## Public Resources

- **Reproducible Google Colab Notebook:** https://colab.research.google.com/github/24127226/16-FIM-DATA-MINING/blob/main/notebooks/demo.ipynb
- **Public Dataset Repository (Hugging Face, no login required):** https://huggingface.co/datasets/cuongnguyen0794/16-fim-data-mining
- **Project Report (LaTeX source & PDF):** [`docs/report/`](docs/report/)

---

## Environment Setup

- **Julia:** `1.11.4` (recommended via `juliaup`)
- **Java:** `≥ 25` (required only when running the SPMF reference binary `spmf.jar` for black-box verification and benchmarking)

```bash
# 1. Instantiate core package dependencies
julia --project=. -e "using Pkg; Pkg.instantiate()"

# 2. Download benchmark and application datasets (auto-verified via SHA-256 from Hugging Face)
julia --project=. scripts/fetch_data.jl benchmark groceries

# 3. Download SPMF reference binary (optional, for cross-checking against SPMF)
julia --project=. scripts/fetch_spmf.jl
```

---

## Command-Line Usage (`demo.jl`)

```bash
julia --project=. demo.jl [options] --minsup <threshold> <input_file>
```

**Options:**
- `--minsup 0.01 | 1%`: required support threshold in `(0, 1]` or `(0%, 100%]`.
- `-o, --output FILE`: SPMF-formatted output path (default: `output.txt`; use `"-"` to stream patterns to `stdout`).
- `--variant v0..v6`: Eclat variant to execute (default: `v6`).
- `--stats`: report internal counters (`EclatStats`; disabled during timing runs).
- `-h, --help`: display usage information.

**Example on canonical toy datasets:**

```bash
julia --project=. demo.jl --minsup 40% -o - data/toy/pasquier99.txt
julia --project=. demo.jl --minsup 0.5 --stats -o output.txt data/toy/bookstore.txt
```

Expected counts: `pasquier99.txt` at `40%` produces **15** frequent itemsets; `bookstore.txt` at `0.5` produces **19** frequent itemsets.

---

## Automated Verification (`test/runtests.jl`)

Run the three-tier test suite (SPMF I/O & `minsup_count` boundary tests, 200-database brute-force oracle, canonical datasets, edge cases, association rule tests, and 4 benchmark datasets):

```bash
julia --project=. test/runtests.jl
julia --project=. --check-bounds=yes test/runtests.jl
```

**Latest verified test output (Julia `1.11.4`, all 7 variants `v0`–`v6` + 4 benchmarks verified 100% against SPMF):**

```text
Test Summary: |  Pass  Total   Time
EclatFIM      | 10474  10474  11.8s
```

Both default and `--check-bounds=yes` runs pass `10,474 / 10,474` assertions and are automatically verified on every push via GitHub Actions CI (`.github/workflows/ci.yml`).

---

## Benchmarking & Real-World Applications

```bash
# Quick benchmark run (isolated processes with warm-up, 17-column CSV output)
julia --project=. scripts/bench.jl --mode quick --variants v0,v1 --repeats 1 --out results/bench_quick.csv

# Application 1: Market Basket Analysis on Groceries (Tables B08-B10, Figure F11)
julia --project=. apps/groceries/run_groceries.jl

# Generate PDF vector & PNG figures directly from CSV results
julia --project=scripts -e "using Pkg; Pkg.instantiate()"
julia --project=scripts scripts/plots.jl
```

---

## Repository Structure

```text
├── README.md
├── Project.toml, Manifest.toml   # Core EclatFIM package environment (minimal dependencies)
├── demo.jl                       # Standalone SPMF-compatible CLI
├── src/
│   ├── EclatFIM.jl               # Main module exports
│   ├── structures.jl             # TransactionDB, EclatConfig, EclatStats interface contract
│   ├── utils.jl                  # Byte-level read_spmf, minsup_count, buffered SPMFWriter
│   ├── rules.jl                  # Association rule generation and BinaryMinHeap top-k
│   └── algorithm/                # Eclat core implementation (tidsets, equivalence classes)
├── test/                         # Automated unit & benchmark tests (named test/ per required CLI command)
├── data/
│   ├── toy/                      # Small canonical datasets committed to the repository
│   └── benchmark/                # Sources, statistics, and SHA-256 checksums (large files hosted on HF)
├── scripts/                      # Data fetching, SPMF comparator, benchmarking, synthetic/subsample generators, plotting
├── apps/
│   └── groceries/                # Application 1: Market Basket Analysis on Groceries
├── results/                      # Raw CSV results, summary tables, and generated figures
├── notebooks/
│   └── demo.ipynb                # Reproducible Google Colab notebook
└── docs/
    └── report/                   # LaTeX report source (HCMUS template) and compiled PDF
```

*Note:* The test directory is named `test/` (rather than `tests/`) to match the required test command `julia --project test/runtests.jl`.

---

## Data Sources & Reference Binary

- **Benchmark datasets** (`chess`, `mushroom` FIMI 8,124-transaction version, `retail`, `accidents`, `T10I4D100K`) and `groceries.csv` are mirrored publicly at https://huggingface.co/datasets/cuongnguyen0794/16-fim-data-mining with full provenance and SHA-256 checksums recorded in [`data/benchmark/README.md`](data/benchmark/README.md).
- **SPMF reference implementation:** `spmf.jar` (Eclat `v2.65`, SHA-256: `2cc2d89e39909230ea0455da4a1c79b389dc98ca04b0670befb63e679b5e2ea0`), executed strictly as a black-box oracle.

---

## Academic Integrity & AI Usage Statement

All algorithm implementations, I/O routines, verification tools, and application pipelines are written from scratch without copying source code from SPMF or external FIM libraries. No external frequent itemset mining libraries are imported anywhere in this project. AI assistants were used strictly for technical discussion, review, and formatting; all code and experimental analyses are verified and fully understood by both team members.

---

## References

1. M. J. Zaki, "Scalable Algorithms for Association Mining," *IEEE TKDE*, vol. 12, no. 3, pp. 372--390, 2000.
2. P. Fournier-Viger et al., "SPMF: A Java Open-Source Pattern Mining Library," *JMLR*, vol. 15, pp. 3389--3393, 2014.
3. M. Hahsler, B. Grün, and K. Hornik, "arules -- A Computational Environment for Mining Association Rules and Frequent Item Sets," *JSS*, vol. 14, no. 15, pp. 1--25, 2005.
4. S. Brin, R. Motwani, J. D. Ullman, and S. Tsur, "Dynamic Itemset Counting and Implication Rules for Market Basket Data," *ACM SIGMOD*, pp. 255--264, 1997.
