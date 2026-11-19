# Khai thác tập phổ biến bằng Eclat (Julia)

Đồ án môn **Khai thác dữ liệu và ứng dụng** (HCMUS): tự cài đặt lại thuật toán **Eclat** từ bài báo gốc bằng Julia, kiểm chứng với cài đặt tham chiếu SPMF, đánh giá hiệu năng trên 5 bộ benchmark và áp dụng cho hai bài toán thực tế (phân tích giỏ hàng, mẫu trực quan trên ảnh).

> M. J. Zaki, "Scalable Algorithms for Association Mining", *IEEE Transactions on Knowledge and Data Engineering* 12(3):372–390, 2000. [PDF](https://www.cs.rpi.edu/~zaki/PaperDir/TKDE00.pdf)

[![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/TAI_KHOAN/GROUP_ID/blob/main/notebooks/demo.ipynb)

| | Liên kết |
|---|---|
| Notebook demo (Google Colab, chạy được không cần đăng nhập) | [notebooks/demo.ipynb trên Colab](https://colab.research.google.com/github/TAI_KHOAN/GROUP_ID/blob/main/notebooks/demo.ipynb) |
| Báo cáo | [docs/Report.pdf](docs/Report.pdf) |
| Dữ liệu benchmark trên Hugging Face | [huggingface.co/datasets/TAI_KHOAN/TEN_DATASET](https://huggingface.co/datasets/TAI_KHOAN/TEN_DATASET) |
| Số liệu thực nghiệm (CSV), bảng, hình | [results/](results/) |

## Thành viên

| Họ tên | MSSV | Phụ trách |
|---|---|---|
| Phạm Trần Anh Quân | ……… | Thuật toán và hiệu năng: `src/algorithm/`, các tối ưu v1–v6, ablation (E7, E8, E10), Ứng dụng 2 |
| Nguyễn Tiến Cường | ……… | Kiểm chứng, thực nghiệm và dữ liệu: đọc/ghi SPMF, CLI, kiểm thử, E1–E6, E9, Ứng dụng 1, notebook |

Cả hai thành viên cùng review code của nhau và đều giải thích được toàn bộ bài làm.

## Kết quả chính

| Hạng mục | Kết quả | Chi tiết |
|---|---|---|
| Tính đúng | **Khớp SPMF 100%**: 245/245 tổ hợp (5 bộ benchmark × 7 mức minsup × 7 phiên bản), khoảng 61 triệu cặp (tập, support); 15.869/15.869 phép kiểm tra tự động đạt | `results/e1_correctness.csv`, báo cáo III.E, IV.B |
| Tốc độ so với SPMF (thời gian thuật toán) | Bản mặc định v6 nhanh hơn SPMF `Eclat` ở cả 35 mức minsup (2,7–285 lần) và nhanh hơn `Eclat_bitset` ở 34/35 mức (trung vị 2,6 lần trên dữ liệu dày, 4,3 lần trên dữ liệu thưa) | `results/e2_runtime.csv`, hình F03 |
| Thời gian tiến trình | Julia mất 4,5–6 giây để khởi động và biên dịch JIT, nên với các lần chạy ngắn SPMF xong trước tính từ lúc gõ lệnh | `results/e2_cli.csv`, báo cáo IV.C |
| Tối ưu có đo lường (ablation) | Ở minsup trung bình, phiên bản nhanh nhất trên mỗi bộ nhanh hơn bản cơ bản v0 từ 32 đến 75 lần; tidset đỉnh của v6 nhỏ hơn v0 từ 12 đến 44 lần trên dữ liệu dày | `results/ablation_B03.md`, `results/ablation_B04.md`, `results/e4_memory.csv` |
| Khả năng mở rộng | Tuyến tính theo số giao dịch trên Accidents (R² = 0,976; SPMF 0,981), hệ số góc nhỏ hơn SPMF 3,2 lần | `results/e5_scalability.csv`, hình F06 |
| So với Apriori, FP-Growth (SPMF) | v6 nhanh hơn Apriori ở 33/33 mức chạy xong (trung vị 17 lần) và FP-Growth ở 35/35 mức (trung vị 8,3 lần) | `results/e9_algorithms.csv`, hình F09 |
| Phát hiện từ thực nghiệm | Mảng bit nhanh hơn mảng chỉ số ở mật độ thấp hơn nhiều so với ngưỡng bộ nhớ 1/32, trừ khi hầu hết phép giao thất bại; vì vậy không có phiên bản nào nhanh nhất trên mọi bộ dữ liệu | `results/density_E7.md`, hình F08 |
| Ứng dụng 1 (Groceries) | 120 luật ở minsup 0,5%, minconf 0,5; luật mạnh nhất {curd, tropical fruit} ⇒ {yogurt} (lift 3,69); 127/127 luật tìm trên 80% dữ liệu vẫn có lift > 1 trên 20% còn lại | `results/apps/groceries/` |
| Ứng dụng 2 (Caltech-101) | Mẫu trực quan đặc trưng cho từng lớp; dùng 80 mẫu làm đặc trưng đạt 75,8% độ chính xác (kết hợp histogram: 86,7%); mẫu của lớp khuôn mặt làm lộ thiên lệch phông nền | `results/apps/bovw/`, hình F12, F13 |

Mọi số đo thời gian lấy trên một máy (Intel Core i5-6200U, 10 GiB RAM, Windows 10; `results/ENV.md`), trung vị của 3–5 lần chạy; nhật ký từng lần chạy ở `results/LOG.md`.

## Chuẩn bị môi trường

- **Julia 1.11.4** (bản dùng để đo; mọi bản Julia 1.11 đều chạy được). Cách dễ nhất là cài [juliaup](https://julialang.org/downloads/) rồi chạy `juliaup add 1.11.4` và `juliaup default 1.11.4`.
- **Java ≥ 25**: chỉ cần khi chạy SPMF để đối chiếu kết quả hoặc đo hiệu năng; bản `spmf.jar` hiện tại được biên dịch cho Java 25.

Từ gốc repo:

```
julia --project=. -e "using Pkg; Pkg.instantiate()"
julia --project=. scripts/fetch_data.jl benchmark      # 5 bộ benchmark, kiểm tra SHA-256
julia --project=. scripts/fetch_spmf.jl                # spmf.jar (chỉ khi cần đối chiếu với SPMF)
```

Gói ngoài duy nhất của phần thuật toán là `DataStructures.jl` (lấy top-k luật bằng heap). Các script vẽ hình (`scripts/`) và hai ứng dụng (`apps/`) có môi trường riêng để không kéo thư viện vẽ vào phần lõi:

```
julia --project=scripts -e "using Pkg; Pkg.instantiate()"
julia --project=apps -e "using Pkg; Pkg.instantiate()"
```

## Cách chạy

Đúng lệnh mẫu của đề (`data/benchmark.txt` là một file SPMF bất kỳ, ví dụ chép từ `data/benchmark/retail.txt`):

```
julia --project=. demo.jl --minsup 0.01 data/benchmark.txt
```

Một vài ví dụ khác:

```
julia --project=. demo.jl --minsup 40% data/toy/pasquier99.txt -o -
julia --project=. demo.jl --minsup 0.8 data/benchmark/chess.txt -o chess_80.txt --stats
julia --project=. demo.jl --minsup 50% data/toy/bookstore.txt --variant v0 -o -
```

| Tùy chọn | Ý nghĩa |
|---|---|
| `--minsup 0.01` hoặc `--minsup 1%` | Bắt buộc. Tỉ lệ trong (0, 1] hoặc phần trăm; σ_min = ⌈minsup · N⌉ tính giống hệt SPMF |
| `-o`, `--output FILE` | File kết quả (mặc định `output.txt`; `-` để in ra màn hình) |
| `--variant v0..v6` | Phiên bản thuật toán (mặc định v6, bản lai; xem bảng dưới) |
| `--maxlen K` | Chỉ tìm các tập có tối đa K item |
| `--stats` | In thêm bộ đếm: số phép giao, số lớp, tập dài nhất, bộ nhớ tidset đỉnh |
| `-h`, `--help` | In hướng dẫn |

Output mong đợi của ví dụ đầu tiên trong khối trên (`pasquier99.txt` là dữ liệu ví dụ `contextPasquier99` của SPMF, minsup 40% → σ_min = 2; đúng 15 tập như tài liệu SPMF). Thứ tự các dòng có thể khác SPMF; bộ so sánh của nhóm không phụ thuộc thứ tự.

```
1 #SUP: 3
1 2 #SUP: 2
1 2 3 #SUP: 2
1 2 3 5 #SUP: 2
1 2 5 #SUP: 2
1 3 #SUP: 3
1 3 5 #SUP: 2
1 5 #SUP: 2
2 #SUP: 4
2 3 #SUP: 3
2 3 5 #SUP: 3
2 5 #SUP: 4
3 #SUP: 4
3 5 #SUP: 3
5 #SUP: 4
EclatFIM: Eclat (Zaki, 2000), phiên bản v6
  Input     : data/toy/pasquier99.txt (N = 5 giao dịch, m = 5 item)
  minsup    : 40% → σ_min = 2 giao dịch
  Kết quả   : 15 tập phổ biến → màn hình
  Thời gian : đọc 0.0 s | khai thác + ghi 1.074 s 
```

**Input:** định dạng SPMF, mỗi dòng một giao dịch, các item là số nguyên không âm cách nhau bằng khoảng trắng; dòng rỗng và dòng bắt đầu bằng `#`, `%`, `@` được bỏ qua. **Output:** mỗi dòng một tập phổ biến, `i1 i2 … #SUP: s`, item theo mã gốc tăng dần. Mã thoát: 0 thành công, 1 tham số sai, 2 lỗi dữ liệu.

Dùng như một thư viện Julia:

```julia
using EclatFIM
db = read_spmf("data/toy/bookstore.txt")
σ = minsup_count(parse_minsup("50%"), n_transactions(db))   # 3 giao dịch
res = eclat(db, σ)                    # Dict{Vector{Int32},Int}: tập (mã nội bộ) => support
length(res)                           # 19 tập, đúng như Fig. 1 của bài báo
```

### Các phiên bản (ablation)

Mỗi phiên bản thêm đúng một thay đổi so với phiên bản trước, để đo được tác dụng của từng tối ưu (báo cáo mục III.D).

| Phiên bản | Thay đổi |
|---|---|
| v0 | Bản cơ bản theo bài báo: tidset là mảng chỉ số tăng dần, cấp phát mới cho mỗi tidset, item theo thứ tự mã, mức 2 bằng giao từng cặp |
| v1 | + sắp item theo support tăng dần |
| v2 | + dùng lại bộ nhớ đệm theo từng độ sâu (không cấp phát trong vòng lặp nóng) |
| v3 | + phép giao thích nghi: dừng sớm khi không thể đạt σ_min, tìm kiếm phi mã (galloping) khi hai tidset chênh lệch nhiều |
| v4 | + tidset dạng mảng bit (`BitVector`, phép AND theo word 64 bit) |
| v5 | + đếm tập 2 item bằng mảng tam giác (§5.1 của bài báo) |
| v6 | + biểu diễn lai: chuyển từ mảng bit sang mảng chỉ số khi tidset đủ thưa (σ < N/32) |

## Kiểm thử

```
julia --project test/runtests.jl
```

Ba tầng kiểm chứng độc lập: oracle duyệt trâu trên 200 CSDL ngẫu nhiên; đáp án SPMF cho 11 ca (toy, ví dụ trong bài báo, ca biên) và dấu vân tay trên 5 bộ benchmark; thí nghiệm E1 trên toàn bộ lưới minsup. Mọi phép kiểm tra tính đúng chạy trên cả 7 phiên bản. Phần "Benchmark" tự bỏ qua nếu chưa tải dữ liệu. GitHub Actions chạy lại bộ test ở mỗi lần push, kể cả với `--check-bounds=yes`.

Output của lần chạy cuối (Windows 10, Julia 1.11.4, 18/11/2026):

```
$ julia --project test/runtests.jl
[ Info: Các phiên bản được kiểm thử: v0, v1, v2, v3, v4, v5, v6
[ Info: Bộ nhớ cấp phát: v0 = 9.91 MiB, v2 = 0.27 MiB
Test Summary:                            |  Pass  Total   Time
EclatFIM                                 | 15869  15869  47.9s
  Đọc/ghi và minsup                      |    51     51   4.7s
  Tính đúng                              |  5276   5276  15.1s
  Hàm lõi và hiệu năng                   | 10006  10006   2.8s
  Luật kết hợp                           |   431    431   2.0s
  Benchmark (đối chiếu dấu vân tay SPMF) |   105    105  23.2s
```

**Tỉ lệ khớp với SPMF** = số tập có ở cả hai bên với cùng support ÷ số tập ở hợp của hai bên. Kết quả: **100%** trên mọi ca kiểm thử, và cả **245/245** tổ hợp (5 bộ benchmark × 7 mức minsup × 7 phiên bản) của thí nghiệm E1 (`results/e1_correctness.csv`).

Đối chiếu nhanh với SPMF trên một file bất kỳ:

```
julia --project=. scripts/compare_spmf.jl data/benchmark/chess.txt 80%
```

## Tái lập thực nghiệm (Chương 2)

Giao thức đo: mỗi lần đo là một tiến trình Julia mới, có chạy khởi động trên dữ liệu toy để loại thời gian biên dịch JIT, lặp 3 lần (5 lần nếu dưới 1 giây) và lấy trung vị, giới hạn 10 phút mỗi lần chạy; SPMF chạy với `-Xmx8g`. Cấu hình máy đo ở `results/ENV.md`; mỗi lần chạy script được ghi vào `results/LOG.md`.

```
julia --project=. scripts/fetch_data.jl benchmark
julia --project=. scripts/fetch_spmf.jl
julia --project=. scripts/subsample.jl retail          # tập con 10/25/50/75/100% cho E5
julia --project=. scripts/subsample.jl accidents
julia --project=. scripts/gen_synthetic.jl              # dữ liệu tổng hợp cho E6, E7
julia --project=. scripts/bench.jl all                  # E1, E2, E4, E5, E6, E9
julia --project=. scripts/bench_cli.jl                  # E2b: thời gian tiến trình thật của demo.jl
julia --project=. scripts/bench_ablation.jl             # E8 (bảng B03, B04)
julia --project=. scripts/bench_density.jl              # E7
julia --project=. scripts/bench_memory_trace.jl         # E10 (Chess và T10I4D100K)
julia --project=scripts scripts/plots.jl                # hình F03–F07, F09, F11
julia --project=scripts scripts/plots_a.jl              # hình F08, F10
```

| Thí nghiệm | Nội dung | Kết quả thô | Hình/bảng |
|---|---|---|---|
| E1 | Tính đúng: mọi phiên bản × mọi mức minsup so với SPMF | `results/e1_correctness.csv` | B05 |
| E2, E3 | Thời gian và số tập phổ biến theo minsup | `results/e2_runtime.csv` | F03, F04 |
| E2b | Thời gian tiến trình thật của `demo.jl` (gồm khởi động, JIT) | `results/e2_cli.csv` | báo cáo IV.C |
| E4 | Bộ nhớ đỉnh tại minsup trung bình | `results/e4_memory*.csv` | F05 |
| E5 | Khả năng mở rộng trên tập con của Retail và Accidents | `results/e5_scalability.csv` | F06 |
| E6 | Ảnh hưởng của độ dài giao dịch (dữ liệu tổng hợp) | `results/e6_length.csv` | F07 |
| E7 | Mảng bit hay mảng chỉ số theo mật độ | `results/density.csv` | F08 |
| E8 | Ablation v0 → v6 | `results/ablation*.csv` | B03, B04 |
| E9 | So với Apriori và FP-Growth của SPMF | `results/e9_algorithms.csv` | F09 |
| E10 | Bộ nhớ tidset theo tiến trình duyệt | `results/memory_trace.csv` | F10 |

Lưới minsup (7 mức mỗi bộ, chọn trước khi đo chính thức): `results/minsup_grid.md`. Toàn bộ thực nghiệm mất khoảng 4,5 giờ trên máy đo. Notebook có chế độ nhanh chạy lại một phần E1, E2, E4, E5, E8 trên Colab (vào thư mục riêng `results_colab/`, không ghi đè số liệu chính thức) rồi vẽ lại mọi hình từ CSV.

## Ứng dụng (Chương 3)

```
julia --project=. scripts/fetch_data.jl groceries caltech
julia --project=. apps/groceries/prepare.jl         # Ứng dụng 1: Groceries → định dạng SPMF
julia --project=. apps/groceries/analyze.jl         #   luật kết hợp, top-10 theo lift, độ ổn định
julia --project=apps apps/bovw/prepare.jl           # Ứng dụng 2: descriptor, codebook k-means++
julia --project=apps apps/bovw/analyze.jl           #   ảnh → giao dịch, mẫu đặc trưng, phân lớp
julia --project=apps apps/bovw/figures.jl           #   hình F12, F13
```

Kết quả nằm trong `results/apps/groceries/` (B08–B10) và `results/apps/bovw/` (B11–B13). Mọi tập phổ biến của hai ứng dụng đều do Eclat của nhóm tìm ra; phần trích đặc trưng ảnh (descriptor gradient, k-means++) cũng do nhóm tự viết, thư viện ngoài chỉ dùng để giải mã file JPEG.

## Cấu trúc thư mục

```
├── README.md
├── Project.toml, Manifest.toml   # môi trường Julia của phần lõi (module EclatFIM)
├── demo.jl                       # giao diện dòng lệnh
├── src/
│   ├── EclatFIM.jl               # module chính
│   ├── structures.jl             # cấu trúc dữ liệu: TransactionDB, EclatConfig (v0–v6), EclatStats
│   ├── utils.jl                  # đọc/ghi định dạng SPMF, minsup, so sánh kết quả, dấu vân tay
│   ├── rules.jl                  # sinh luật kết hợp, top-k
│   └── algorithm/                # cài đặt chính: eclat.jl, tidsets.jl (các phép giao), level2.jl
├── test/                         # kiểm thử tự động: runtests.jl, test_correctness.jl, test_benchmark.jl, ...
├── data/
│   ├── toy/                      # CSDL nhỏ để kiểm thử nhanh
│   ├── benchmark/                # nguồn, thống kê, SHA-256 (file lớn không commit)
│   └── huggingface/              # mô tả dataset trên Hugging Face
├── scripts/                      # tải dữ liệu, đối chiếu SPMF, thực nghiệm, vẽ hình
├── apps/                         # Ứng dụng 1 (groceries/) và Ứng dụng 2 (bovw/)
├── results/                      # số liệu thô (CSV), bảng (Markdown), hình (PDF/PNG)
├── notebooks/demo.ipynb          # notebook demo chạy trên Google Colab
└── docs/
    ├── Report.pdf                # báo cáo
    └── report/                   # mã nguồn LaTeX của báo cáo (IEEE, XeLaTeX)
```

Thư mục kiểm thử tên là `test/` (không phải `tests/` như cấu trúc gợi ý của đề) vì đây là quy ước của Julia: `Pkg.test()` chỉ tìm `test/runtests.jl`, và lệnh kiểm thử trong đề (`julia --project test/runtests.jl`) cũng dùng đường dẫn này.

## Dữ liệu

| Bộ | N | m | L̄ | Loại |
|---|---|---|---|---|
| Chess | 3.196 | 75 | 37,0 | dày |
| Mushroom | 8.124 | 119 | 23,0 | dày |
| Accidents | 340.183 | 468 | 33,8 | dày, lớn |
| Retail | 88.162 | 16.470 | 10,3 | thưa |
| T10I4D100K | 100.000 | 870 | 10,1 | thưa, tổng hợp |

Thống kê do nhóm tự đo lại và khớp bảng của đề. Nguồn, SHA-256 và các lưu ý (ví dụ Mushroom có hai phiên bản) ở [data/benchmark/README.md](data/benchmark/README.md). Bản lưu trữ dùng cho notebook nằm trên Hugging Face (liên kết ở đầu trang); `scripts/fetch_data.jl` thử Hugging Face trước rồi đến nguồn gốc, và luôn kiểm tra SHA-256. Hai ứng dụng dùng Groceries (gói R `arules`) và Caltech-101 (giấy phép CC BY 4.0).

## Cài đặt tham chiếu SPMF

Kết quả được đối chiếu với SPMF (thuật toán `Eclat` v2.65, `spmf.jar` có SHA-256 `2cc2d89e39909230ea0455da4a1c79b389dc98ca04b0670befb63e679b5e2ea0`). SPMF chỉ được chạy như một hộp đen qua dòng lệnh: nhóm không đọc và không dùng mã nguồn của SPMF. Các quy tắc như cách đổi minsup sang số đếm được xác định bằng thí nghiệm hộp đen (`results/spmf_behavior.md`). `spmf.jar` không được commit; tải bằng `scripts/fetch_spmf.jl`.

## Liêm chính học thuật và sử dụng AI

- Toàn bộ mã được nhóm viết dựa trên mô tả trong bài báo gốc; nhóm không sao chép mã từ SPMF hay bất kỳ cài đặt có sẵn nào.
- Nhóm có dùng trợ lý AI (Claude) để hỗ trợ viết code, kiểm thử và tài liệu, đúng như đề cho phép. Mọi phần đều đã được cả hai thành viên đọc, chạy lại và giải thích được; lịch sử commit thể hiện phần việc của từng người.

## Tài liệu tham khảo

1. M. J. Zaki, "Scalable algorithms for association mining," *IEEE TKDE*, 12(3):372–390, 2000.
2. R. Agrawal, R. Srikant, "Fast algorithms for mining association rules," *VLDB*, 1994.
3. J. Han, J. Pei, Y. Yin, "Mining frequent patterns without candidate generation," *SIGMOD*, 2000.
4. M. J. Zaki, K. Gouda, "Fast vertical mining using diffsets," *KDD*, 2003.
5. P. Fournier-Viger et al., "SPMF: a Java open-source pattern mining library," *JMLR*, 15:3389–3393, 2014.
6. B. Goethals, M. J. Zaki, "Advances in frequent itemset mining implementations: report on FIMI'03," *SIGKDD Explorations*, 6(1), 2004.
7. M. Hahsler, B. Grün, K. Hornik, "arules: a computational environment for mining association rules and frequent item sets," *Journal of Statistical Software*, 14(15), 2005.
8. L. Fei-Fei, R. Fergus, P. Perona, "Learning generative visual models from few training examples," *CVPR Workshop*, 2004.

Danh sách đầy đủ ở báo cáo (`docs/report/references.bib`).
