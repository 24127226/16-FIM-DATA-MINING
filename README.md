# Khai thác tập phổ biến bằng thuật toán Eclat (Julia)

Đồ án môn **Khai thác dữ liệu và ứng dụng** (Khoa Công nghệ Thông tin, Trường Đại học Khoa học Tự nhiên — ĐHQG-HCM): tự cài đặt thuật toán **Eclat** theo bài báo gốc, kiểm chứng tính đúng đắn với cài đặt tham chiếu SPMF, đánh giá hiệu năng trên các bộ dữ liệu benchmark và triển khai hai ứng dụng thực tế.

> M. J. Zaki, "Scalable Algorithms for Association Mining", *IEEE Transactions on Knowledge and Data Engineering*, vol. 12, no. 3, pp. 372–390, 2000. [PDF](https://www.cs.rpi.edu/~zaki/PaperDir/TKDE00.pdf)

## Thành viên thực hiện

| Họ và tên | MSSV | Phân công chính |
|---|---|---|
| Phạm Trần Anh Quân | 24127226 | Thuật toán Eclat, tối ưu hiệu năng và Ứng dụng 2 (BoVW) |
| Nguyễn Tiến Cường | 24127337 | I/O chuẩn SPMF, kiểm chứng, hạ tầng thực nghiệm, Ứng dụng 1 (Groceries), Notebook và tài liệu |

## Tài nguyên công khai

- **Tập dữ liệu công khai (Hugging Face, truy cập không cần đăng nhập):** https://huggingface.co/datasets/cuongnguyen0794/16-fim-data-mining
- **Notebook tái lập trên Google Colab:** https://colab.research.google.com/github/24127226/16-FIM-DATA-MINING/blob/main/notebooks/demo.ipynb

## Yêu cầu môi trường và thực thi

- **Julia:** phiên bản `1.11.4`
- **Java:** phiên bản `≥ 25` (phục vụ chạy cài đặt tham chiếu `spmf.jar` khi đối chiếu kết quả)

```bash
julia --project=. -e "using Pkg; Pkg.instantiate()"
julia --project=. scripts/fetch_data.jl benchmark groceries
julia --project=. scripts/fetch_spmf.jl
julia --project=. test/runtests.jl
```

### Giao diện dòng lệnh (`demo.jl`)

```bash
julia --project=. demo.jl --minsup 0.4 data/toy/pasquier99.txt
julia --project=. demo.jl --minsup 50% --stats -o output.txt data/toy/bookstore.txt
```

## Cấu trúc thư mục

```text
├── README.md
├── Project.toml, Manifest.toml   # môi trường gói chính EclatFIM
├── demo.jl                       # giao diện dòng lệnh chuẩn SPMF
├── src/                          # mã nguồn chính (module EclatFIM)
├── test/                         # bộ kiểm thử tự động (chọn test/ theo lệnh chuẩn của đề)
├── data/
│   ├── toy/                      # tập dữ liệu nhỏ phục vụ kiểm thử đơn vị
│   └── benchmark/                # nguồn, thống kê và mã băm SHA-256 (tệp lớn không commit)
├── scripts/                      # tải dữ liệu, đối chiếu SPMF, thực nghiệm và vẽ biểu đồ
├── apps/                         # mã nguồn hai ứng dụng thực tế (Chương 3)
├── results/                      # dữ liệu CSV thô, biểu đồ và tệp tổng hợp kết quả
├── notebooks/                    # notebook tái lập kết quả trên Google Colab
└── docs/                         # mã nguồn LaTeX và báo cáo PDF
```
