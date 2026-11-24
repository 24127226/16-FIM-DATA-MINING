# Khai thác tập phổ biến bằng Eclat (Julia)

Đồ án môn **Khai thác dữ liệu và ứng dụng**: tự cài đặt lại thuật toán **Eclat** từ bài báo gốc, kiểm chứng với cài đặt tham chiếu SPMF, đánh giá hiệu năng trên các bộ benchmark và áp dụng cho hai bài toán thực tế.

> M. J. Zaki, "Scalable Algorithms for Association Mining", *IEEE TKDE* 12(3):372–390, 2000. [PDF](https://www.cs.rpi.edu/~zaki/PaperDir/TKDE00.pdf)

## Thành viên

| Họ tên | MSSV | Vai trò |
|---|---|---|
| Phạm Trần Anh Quân | ……… | Thuật toán & Hiệu năng |
| Nguyễn Tiến Cường | ……… | Kiểm chứng, Thực nghiệm & Dữ liệu |

## Trạng thái

🚧 Đang phát triển. Hướng dẫn cài đặt, cách chạy, kết quả kiểm thử và link Colab sẽ được bổ sung theo từng mốc.

- **Dữ liệu công khai (Hugging Face, không cần đăng nhập):** https://huggingface.co/datasets/cuongnguyen0794/16-fim-data-mining

## Chuẩn bị môi trường

- Julia **1.11.4**
- Java **≥ 25** (để chạy SPMF khi đối chiếu kết quả)

```
julia --project=. -e "using Pkg; Pkg.instantiate()"
julia --project=. scripts/fetch_data.jl benchmark
julia --project=. scripts/fetch_spmf.jl
```

## Cấu trúc thư mục

```
├── README.md
├── Project.toml, Manifest.toml
├── src/                 # cài đặt chính (module EclatFIM)
├── test/                # kiểm thử tự động
├── data/
│   ├── toy/             # CSDL nhỏ để kiểm thử nhanh
│   └── benchmark/       # nguồn và SHA-256 của dữ liệu benchmark (file lớn không commit)
├── scripts/             # tải dữ liệu, đối chiếu SPMF, thực nghiệm, vẽ hình
├── results/             # kết quả thực nghiệm (CSV, hình, ghi chú)
├── notebooks/           # notebook demo chạy trên Google Colab
└── docs/                # báo cáo (Report.pdf)
```
