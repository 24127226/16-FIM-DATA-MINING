# Khai thác tập phổ biến bằng thuật toán Eclat (Julia)

[![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/24127226/16-FIM-DATA-MINING/blob/main/notebooks/demo.ipynb)

Đồ án môn học **CSC14004 -- Khai thác dữ liệu và Ứng dụng** (Lớp `24KHMT1`, Học kỳ 1, Năm học 2026--2027), Khoa Công nghệ Thông tin, Trường Đại học Khoa học Tự nhiên, ĐHQG-HCM.

Kho mã nguồn này cung cấp cài đặt hoàn toàn từ đầu bằng ngôn ngữ **Julia 1.11.4** cho thuật toán **Eclat** trong bài toán khai thác tập phổ biến (*Frequent Itemset Mining* -- FIM), dựa trên biểu diễn dọc (*vertical tidset*) và phân hoạch lớp tương đương theo tiền tố (*prefix-based equivalence classes*) trong bài báo gốc:

> M. J. Zaki, "Scalable Algorithms for Association Mining," *IEEE Transactions on Knowledge and Data Engineering*, vol. 12, no. 3, pp. 372--390, 2000. [PDF](https://www.cs.rpi.edu/~zaki/PaperDir/TKDE00.pdf)

---

## Thành viên nhóm

| Họ và tên | MSSV | Phụ trách chính |
|---|---|---|
| Phạm Trần Anh Quân | `24127226` | Thuật toán Eclat lõi (`v0`--`v6`), tối ưu hóa hiệu năng, phân tích độ phức tạp, thí nghiệm E7/E8/E10 và Ứng dụng 2 (BoVW) |
| Nguyễn Tiến Cường | `24127337` | I/O chuẩn SPMF & CLI, kiểm thử tự động & CI, khung benchmark (E1--E6, E9), Ứng dụng 1 (`Groceries`), notebook Colab và biên soạn tài liệu |

- **Giảng viên lý thuyết:** GS.TS. Lê Hoài Bắc
- **Giảng viên thực hành:** ThS. Huỳnh Lâm Hải Đăng
- **Trợ giảng:** ThS. Nguyễn Ngọc Đức

---

## Tài nguyên công khai

- **Notebook demo chạy trực tiếp trên Google Colab:** https://colab.research.google.com/github/24127226/16-FIM-DATA-MINING/blob/main/notebooks/demo.ipynb
- **Kho dữ liệu công khai (Hugging Face, không cần đăng nhập):** https://huggingface.co/datasets/cuongnguyen0794/16-fim-data-mining
- **Báo cáo đồ án (định dạng IEEE Conference Format, tiếng Việt):** [`docs/Report.pdf`](docs/Report.pdf) ([mã nguồn LaTeX](docs/report/))

---

## Cài đặt môi trường

- **Julia:** `1.11.4` (khuyến nghị cài qua `juliaup`)
- **Java:** `≥ 25` (chỉ cần khi chạy tệp tham chiếu `spmf.jar` để kiểm chứng hộp đen và đo so sánh)

```bash
# 1. Cài đặt các gói phụ thuộc tối thiểu cho gói lõi
julia --project=. -e "using Pkg; Pkg.instantiate()"

# 2. Tải dữ liệu benchmark và ứng dụng (tự động kiểm tra SHA-256 từ Hugging Face)
julia --project=. scripts/fetch_data.jl benchmark groceries

# 3. Tải tệp tham chiếu SPMF (tùy chọn, dùng khi đối chiếu với SPMF)
julia --project=. scripts/fetch_spmf.jl
```

---

## Hướng dẫn chạy dòng lệnh (`demo.jl`)

```bash
julia --project=. demo.jl [tùy chọn] --minsup <ngưỡng> <tệp_đầu_vào>
```

**Các tham số dòng lệnh:**
- `--minsup 0.01 | 1%`: ngưỡng hỗ trợ tối thiểu bắt buộc, thuộc `(0, 1]` hoặc `(0%, 100%]`.
- `-o, --output FILE`: đường dẫn tệp kết quả chuẩn SPMF (mặc định: `output.txt`; truyền `"-"` để xuất trực tiếp ra `stdout`).
- `--variant v0..v6`: biến thể Eclat cần chạy (mặc định: `v6`).
- `--stats`: in các bộ đếm nội bộ (`EclatStats`; tắt hoàn toàn khi đo thời gian).
- `-h, --help`: hiển thị hướng dẫn sử dụng.

**Ví dụ chạy nhanh trên tập dữ liệu mẫu (*toy datasets*):**

```bash
julia --project=. demo.jl --minsup 40% -o - data/toy/pasquier99.txt
julia --project=. demo.jl --minsup 0.5 --stats -o output.txt data/toy/bookstore.txt
```

Kết quả kỳ vọng: `pasquier99.txt` tại `40%` sinh **15** tập phổ biến; `bookstore.txt` tại `0.5` sinh **19** tập phổ biến.

---

## Kiểm thử tự động (`test/runtests.jl`)

Chạy bộ kiểm thử ba tầng (I/O chuẩn SPMF & các ca biên `minsup_count`, oracle vét cạn trên 200 CSDL ngẫu nhiên, tập chuẩn, trường hợp biên, luật kết hợp và đối chiếu trên 4 tập benchmark):

```bash
julia --project=. test/runtests.jl
julia --project=. --check-bounds=yes test/runtests.jl
```

**Output lần chạy kiểm thử gần nhất (Julia `1.11.4`, đủ 7 biến thể `v0`--`v6` + khớp 100% với SPMF trên 4 tập benchmark):**

```text
Test Summary: |  Pass  Total   Time
EclatFIM      | 10474  10474  12.2s
```

Cả hai chế độ mặc định và `--check-bounds=yes` đều đạt `10,474 / 10,474` khẳng định và được kiểm tra tự động sau mỗi lần push qua GitHub Actions CI (`.github/workflows/ci.yml`).

---

## Thực nghiệm Chương 2 & Ứng dụng Chương 3

```bash
# Chạy benchmark nhanh (mỗi lần đo trong tiến trình độc lập có warm-up, xuất CSV 17 cột)
julia --project=. scripts/bench.jl --mode quick --variants v0,v6 --repeats 1 --out results/bench_quick.csv

# Ứng dụng 1: Phân tích giỏ hàng trên Groceries (Bảng B08--B10, Hình F11)
julia --project=. apps/groceries/run_groceries.jl

# Sinh biểu đồ PDF vector & PNG từ tệp kết quả CSV
julia --project=scripts -e "using Pkg; Pkg.instantiate()"
julia --project=scripts scripts/plots.jl

# Thí nghiệm tối ưu hóa: E8 phân rã v0--v6 (Bảng B03, B04), E7 mật độ bitset/tid list, E10 diễn biến bộ nhớ
julia --project=. scripts/bench_ablation.jl
julia --project=. scripts/bench_density.jl
julia --project=. scripts/bench_memory_trace.jl

# Ứng dụng 2: Khám phá mẫu trực quan qua Bag of Visual Words trên Caltech-101 (Bảng B11--B13, Hình F12--F13)
julia --project=apps -e "using Pkg; Pkg.instantiate()"
julia --project=. scripts/fetch_data.jl caltech
julia --project=apps apps/bovw/prepare.jl
julia --project=apps apps/bovw/analyze.jl
julia --project=apps apps/bovw/figures.jl
julia --project=apps scripts/plots_a.jl          # Hình F08, F10 từ kết quả E7/E10
```

---

## Cấu trúc kho mã nguồn

```text
├── README.md
├── Project.toml, Manifest.toml   # Môi trường gói lõi EclatFIM (phụ thuộc tối thiểu)
├── demo.jl                       # Công cụ dòng lệnh (CLI) chuẩn SPMF
├── src/
│   ├── EclatFIM.jl               # Điểm xuất chính của mô-đun
│   ├── structures.jl             # Hợp đồng dữ liệu TransactionDB, EclatConfig, EclatStats
│   ├── utils.jl                  # Bộ đọc cấp byte read_spmf, minsup_count, SPMFWriter
│   ├── rules.jl                  # Sinh luật kết hợp và trích xuất top-k bằng BinaryMinHeap
│   └── algorithm/                # Cài đặt lõi Eclat (tidsets, level2, equivalence classes)
├── test/                         # Bộ kiểm thử tự động (đặt tên test/ theo lệnh chuẩn của đề)
├── data/
│   ├── toy/                      # Các CSDL nhỏ lưu trực tiếp để kiểm thử nhanh
│   └── benchmark/                # Nguồn gốc, thống kê và mã kiểm tra SHA-256 (file lớn trên HF)
├── scripts/                      # Tải dữ liệu, so sánh SPMF, benchmark, sinh dữ liệu, vẽ biểu đồ
├── apps/
│   ├── Project.toml, Manifest.toml  # Môi trường ứng dụng (JpegTurbo, ColorTypes, Plots) cho Ứng dụng 2
│   ├── groceries/                # Ứng dụng 1: Phân tích giỏ hàng trên Groceries
│   └── bovw/                     # Ứng dụng 2: Túi từ thị giác (BoVW) trên Caltech-101
├── results/                      # Dữ liệu đo CSV thô, bảng tổng hợp và biểu đồ đầu ra
├── notebooks/
│   └── demo.ipynb                # Notebook demo tái hiện đầy đủ trên Google Colab
└── docs/
    ├── Report.pdf                # Báo cáo đồ án chính thức (IEEE Conference Format, tiếng Việt)
    └── report/                   # Mã nguồn LaTeX (IEEEtran) và các hình vẽ vector
```

*Ghi chú:* Thư mục kiểm thử được đặt tên `test/` để khớp trực tiếp câu lệnh kiểm thử chuẩn trong đề bài `julia --project test/runtests.jl`.

---

## Nguồn dữ liệu và Tệp tham chiếu SPMF

- **Dữ liệu benchmark & ứng dụng** (`chess`, `mushroom` bản FIMI 8.124 giao dịch, `retail`, `accidents`, `T10I4D100K`, `groceries.csv` và `caltech-101.zip`) được lưu trữ công khai tại https://huggingface.co/datasets/cuongnguyen0794/16-fim-data-mining kèm đầy đủ nguồn gốc và mã kiểm tra SHA-256 trong [`data/benchmark/README.md`](data/benchmark/README.md).
- **Cài đặt tham chiếu SPMF:** `spmf.jar` (Eclat `v2.65`, SHA-256: `bb371b99b3bfd58fbce6b92e0ea3ccda5f9d1fd173bfe8e40f177672117159ba`), chỉ sử dụng như hộp đen để kiểm chứng kết quả và đo so sánh.

---

## Cam kết liêm chính học thuật và Sử dụng AI

Toàn bộ cài đặt thuật toán Eclat, bộ đọc/ghi I/O, công cụ kiểm chứng và quy trình hai ứng dụng đều do nhóm tự viết từ đầu, không sao chép mã nguồn từ SPMF hay bất kỳ thư viện FIM bên ngoài nào. Không có thư viện khai thác tập phổ biến bên ngoài nào được nhập trong toàn bộ đồ án. Công cụ AI chỉ được sử dụng để hỗ trợ thảo luận kỹ thuật, rà soát và định dạng; mọi đoạn mã và phân tích thực nghiệm đều được cả hai thành viên kiểm chứng và nắm vững để giải thích khi vấn đáp.

---

## Tài liệu tham khảo

1. M. J. Zaki, "Scalable Algorithms for Association Mining," *IEEE TKDE*, vol. 12, no. 3, pp. 372--390, 2000.
2. P. Fournier-Viger et al., "SPMF: A Java Open-Source Pattern Mining Library," *JMLR*, vol. 15, pp. 3389--3393, 2014.
3. M. Hahsler, B. Grün, and K. Hornik, "arules -- A Computational Environment for Mining Association Rules and Frequent Item Sets," *JSS*, vol. 14, no. 15, pp. 1--25, 2005.
4. S. Brin, R. Motwani, J. D. Ullman, and S. Tsur, "Dynamic Itemset Counting and Implication Rules for Market Basket Data," *ACM SIGMOD*, pp. 255--264, 1997.
