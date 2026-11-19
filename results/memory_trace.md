# E10: bộ nhớ tidset theo tiến trình duyệt (giả thuyết H7)

Sinh bởi `scripts/bench_memory_trace.jl`. Đỉnh lấy từ bộ đếm nội bộ; vị trí đỉnh và trung bình lấy trên các điểm lấy mẫu (tối đa 4.000 điểm mỗi lần chạy).

| Bộ | minsup | Phiên bản | Số tập | Tidset đỉnh | Trung bình | Đỉnh / trung bình | Đỉnh tại tập thứ | Độ dài tập lúc đỉnh | Tập dài nhất |
|---|---|---|---|---|---|---|---|---|---|
| chess | 65% | v3 | 111239 | 1.090 MiB | 0.767 MiB | 1.42 | 86805 | 13 | 13 |
| chess | 65% | v4 | 111239 | 0.044 MiB | 0.030 MiB | 1.47 | 86805 | 13 | 13 |
| T10I4D100K | 0.1% | v3 | 27532 | 3.885 MiB | 3.853 MiB | 1.01 | 11970 | 9 | 10 |
| T10I4D100K | 0.1% | v4 | 27532 | 10.076 MiB | 9.713 MiB | 1.04 | 5946 | 9 | 10 |
