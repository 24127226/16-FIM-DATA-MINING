# Nhật ký các lần chạy thực nghiệm

Mỗi script thực nghiệm tự ghi thêm một dòng khi chạy xong (KE_HOACH_DU_AN.md mục 8.5, bước 11).
Cấu hình máy: `results/ENV.md`.

| Thời điểm | Commit | Máy | Lệnh | Thời gian chạy |
|---|---|---|---|---|
| 2026-11-17 22:03 | nogit | DESKTOP-LFG7EP1 | `julia --project=. scripts/bench_memory_trace.jl chess` | ghi tay (chạy trước khi có ghi nhật ký tự động) |
| 2026-11-17 23:05 | nogit | DESKTOP-LFG7EP1 | `julia --project=. scripts/bench.jl E1` | 62.0 phút (ghi tay từ cột date của CSV) |
| 2026-11-17 23:06 | nogit | DESKTOP-LFG7EP1 | `julia --project=. scripts/bench.jl E2 E4 E5` | ghi tay: dừng giữa chừng ở Mushroom 7.5% vì phiên làm việc bị ngắt; giữ các mức đã đo xong, xóa 2 dòng của mức đang đo dở |
| 2026-11-18 10:01 | nogit | DESKTOP-LFG7EP1 | `julia --project=. scripts/bench.jl E2 E4 E5 --resume` | 82.5 phút (đo tiếp từ Mushroom 7.5%) |
| 2026-11-18 10:11 | nogit | DESKTOP-LFG7EP1 | `julia --project=. scripts/bench.jl E5 --resume --datasets accidents` | 4.3 phút (bị nhiễu do máy có tải nền khoảng 39% CPU; đã xóa số liệu và đo lại lúc 10:16 với 5 lần lặp) |
| 2026-11-18 10:16 | nogit | DESKTOP-LFG7EP1 | `julia --project=. scripts/bench.jl E5 --resume --datasets accidents --repeats 5` | 4.7 phút |
| 2026-11-18 10:29 | nogit | DESKTOP-LFG7EP1 | `julia --project=. scripts/bench.jl E6` | 5.0 phút |
| 2026-11-18 10:31 | nogit | DESKTOP-LFG7EP1 | `julia --project=. scripts/bench_cli.jl` | 1.8 phút |
| 2026-11-18 10:54 | nogit | DESKTOP-LFG7EP1 | `julia --project=. scripts/bench_ablation.jl` | 19.9 phút |
| 2026-11-18 11:06 | nogit | DESKTOP-LFG7EP1 | `julia --project=. scripts/bench_density.jl` | 11.7 phút |
| 2026-11-18 11:06 | nogit | DESKTOP-LFG7EP1 | `julia --project=. scripts/bench_memory_trace.jl` | 0.6 phút |
| 2026-11-18 11:40 | nogit | DESKTOP-LFG7EP1 | `julia --project=. scripts/bench.jl E9` | 33.0 phút |
