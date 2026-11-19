# Ứng dụng 2: tập visual word đặc trưng cho từng lớp

Phương án: k = 200, bỏ từ quá phổ biến, thêm "xuất hiện ≥ 2 lần". Khai thác riêng từng lớp trên ảnh huấn luyện (minsup = 30% của lớp, tập 2–3 từ). Xếp theo tỉ lệ tăng GR = s_lớp / s_lớp-khác (∞: không xuất hiện ở lớp khác, "jumping emerging pattern"). Ký hiệu `w×2`: visual word w xuất hiện ít nhất 2 lần trong ảnh (mã item 200 + w).

## airplanes (3089 tập phổ biến trong lớp)

| # | Visual word | s (lớp này) | s (lớp khác) | GR |
|---|---|---|---|---|
| 1 | 31, 41, 146 | 0.36 | 0.000 | ∞ |
| 2 | 31, 146, 171 | 0.36 | 0.000 | ∞ |
| 3 | 118, 146, 146×2 | 0.36 | 0.000 | ∞ |
| 4 | 118, 146×2 | 0.36 | 0.000 | ∞ |
| 5 | 41, 101, 118×2 | 0.33 | 0.000 | ∞ |

## Motorbikes (13134 tập phổ biến trong lớp)

| # | Visual word | s (lớp này) | s (lớp khác) | GR |
|---|---|---|---|---|
| 1 | 63, 139, 192 | 0.31 | 0.005 | 66.0 |
| 2 | 12, 57, 192×2 | 0.30 | 0.005 | 63.0 |
| 3 | 120, 189, 192 | 0.37 | 0.010 | 39.0 |
| 4 | 2, 20, 182 | 0.31 | 0.010 | 33.0 |
| 5 | 29, 120, 137 | 0.31 | 0.010 | 33.0 |

## Faces_easy (4881 tập phổ biến trong lớp)

| # | Visual word | s (lớp này) | s (lớp khác) | GR |
|---|---|---|---|---|
| 1 | 56, 73, 113 | 0.36 | 0.000 | ∞ |
| 2 | 87, 126, 167 | 0.36 | 0.000 | ∞ |
| 3 | 22, 166, 187 | 0.34 | 0.000 | ∞ |
| 4 | 59, 110, 110×2 | 0.34 | 0.000 | ∞ |
| 5 | 59, 110×2 | 0.34 | 0.000 | ∞ |

## watch (6645 tập phổ biến trong lớp)

| # | Visual word | s (lớp này) | s (lớp khác) | GR |
|---|---|---|---|---|
| 1 | 44, 72, 191×2 | 0.30 | 0.010 | 31.5 |
| 2 | 15, 74, 129×2 | 0.31 | 0.014 | 22.0 |
| 3 | 72, 115, 164×2 | 0.30 | 0.014 | 21.0 |
| 4 | 72, 191, 44×2 | 0.30 | 0.014 | 21.0 |
| 5 | 23, 72, 164×2 | 0.33 | 0.019 | 17.2 |

