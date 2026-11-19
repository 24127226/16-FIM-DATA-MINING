# Lưới minsup (chốt ngày 17/11/2026, trước khi đo chính thức)

Chọn theo quy tắc ở KE_HOACH_DU_AN.md mục 8.2, dựa trên chạy thử `scripts/pilot_grid.jl` (kết quả thô: `results/pilot_grid.csv`):

- 7 mức giảm dần cho mỗi bộ: dữ liệu dày cách đều 5 điểm phần trăm; dữ liệu thưa theo dãy 1–2–5 (cách đều trên thang log);
- mức cao nhất có ít nhất khoảng 10 tập phổ biến;
- mức thấp nhất: SPMF Eclat chạy xong trong ≤ 5 phút và output ≤ khoảng 10⁷ tập;
- "minsup trung bình" (dùng cho E4) là mức thứ 4.

| Bộ | Các mức | Mức trung bình | Số tập (cao nhất → thấp nhất) | SPMF Eclat ở mức thấp nhất (chạy thử) |
|---|---|---|---|---|
| chess | 80% → 50% (bước 5) | 65% | 8.227 → 1.272.932 | 79 s |
| mushroom | 30, 25, 20, 15, 10, 7.5, 5% | 15% | 2.735 → 3.755.511 | 23 s (ở 3%: 9,99 triệu tập, sát giới hạn 10⁷ nên không chọn) |
| accidents | 80% → 50% (bước 5) | 65% | 149 → 8.057 | 170 s |
| retail | 1, 0.5, 0.2, 0.1, 0.05, 0.02, 0.01% | 0.1% | 159 → 240.852 | 4,3 s (0,01% tương ứng σ = 9 giao dịch) |
| T10I4D100K | 1, 0.5, 0.2, 0.1, 0.05, 0.02, 0.01% | 0.1% | 385 → 411.365 | 15 s |

Nếu đổi lưới thì phải đo lại toàn bộ E1–E9.
