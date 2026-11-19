# B03: ablation v0 → v6 (thời gian khai thác + ghi kết quả, trung vị)

Tại minsup trung bình của mỗi bộ. Trong ngoặc: tăng tốc so với v0. Sinh bởi `scripts/bench_ablation.jl`.

| Phiên bản | Thay đổi | chess (65%) | mushroom (15%) | accidents (65%) | retail (0.1%) | T10I4D100K (0.1%) |
|---|---|---|---|---|---|---|
| v0 | cơ bản: tidset vector, cấp phát mới mỗi phép giao, thứ tự theo mã | 2.023 s (×1.0) | 1.596 s (×1.0) | 5.290 s (×1.0) | 10.160 s (×1.0) | 4.445 s (×1.0) |
| v1 | + thứ tự item theo support tăng dần | 1.531 s (×1.3) | 1.314 s (×1.2) | 1.850 s (×2.9) | 6.279 s (×1.6) | 4.270 s (×1.0) |
| v2 | + dùng lại buffer theo độ sâu (không cấp phát) | 0.556 s (×3.6) | 0.369 s (×4.3) | 0.904 s (×5.9) | 5.662 s (×1.8) | 3.823 s (×1.2) |
| v3 | + giao thích ứng (ngắt sớm, tìm kiếm nhảy) | 0.891 s (×2.3) | 0.449 s (×3.6) | 0.994 s (×5.3) | 2.024 s (×5.0) | 3.158 s (×1.4) |
| v4 | + tidset dạng bitset (BitVector) | 0.070 s (×29.1) | 0.045 s (×35.7) | 0.081 s (×65.1) | 2.360 s (×4.3) | 0.429 s (×10.4) |
| v5 | + mảng tam giác cho tập 2 item | 0.065 s (×31.1) | 0.050 s (×32.0) | 0.235 s (×22.5) | 0.135 s (×75.4) | 0.137 s (×32.5) |
| v6 | + biểu diễn lai bitset → vector | 0.059 s (×34.0) | 0.048 s (×33.3) | 0.260 s (×20.4) | 0.266 s (×38.2) | 0.470 s (×9.5) |
