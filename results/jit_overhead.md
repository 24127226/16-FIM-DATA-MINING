# Thời gian biên dịch JIT trong lượt đo (kiểm tra ngày 28/11/2026, máy `results/ENV_A.md`)

Thời gian biên dịch đọc bằng `Base.cumulative_compile_time_ns()` trước và sau lượt đo được bấm giờ.

## 1. `scripts/bench.jl` (dùng cho E2–E6, E9): một lượt đo, tiến trình mới

| Phép đo | JIT trong lượt đo (bản cũ, ms) | t_mine_write bản cũ (ms) | t_mine_write bản sửa (ms) |
|---|---|---|---|
| chess 95%, v0 | 47.8 | 50.2 | 1.6 |
| chess 95%, v6 | 283.0 | 290.1 | 2.0 |
| mushroom 70%, v6 | 264.3 | 278.6 | 1.6 |
| retail 0.2%, v6 | 313.2 | 430.1 | 112.6 |
| T10I4D100K 0.2%, v6 | — | — | 229.0 |

Nguyên nhân: bản cũ khởi động bằng một lambda và đo bằng một lambda khác. Mỗi lambda là một kiểu riêng, nên `eclat!` bị
biên dịch lại trong lượt đo. Bản sửa dùng chung hàm `_mine_write` cho cả hai pha.

## 2. `scripts/run_one.jl` (dùng cho E8): v6 trên dữ liệu thưa

| Phép đo | JIT trong lượt đo (bản cũ, ms) | E8 bản cũ (trung vị, ms) | E8 bản sửa (trung vị, ms) |
|---|---|---|---|
| retail 0.2%, v6 | 218.8 | — | — |
| retail 0.1%, v6 | — | 382.3 | 136.3 |
| T10I4D100K 0.2%, v6 | 201.6 | 310.0 | 170.7 |
| T10I4D100K 1%, v6 | — | 197.0 | 33.5 |

Nguyên nhân: dữ liệu khởi động `bookstore.txt` có N = 6, nên ngưỡng N/32 < 1 và v6 không bao giờ đi vào nhánh danh sách tid
lúc khởi động. Bản sửa khởi động thêm trên 2 CSDL của `scripts/warmup.jl`. Sau bản sửa, cột `t_compile_s` của
`e8_ablation.csv` (134 lượt) và `e8_ablation_low.csv` (116 lượt) đều bằng 0. v1–v5 không bị ảnh hưởng: với giao thức cũ,
JIT trong lượt đo của chúng đã bằng 0.

Ô "—": không đo ở giao thức đó.
