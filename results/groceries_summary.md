# Kết quả Ứng dụng 1: Phân tích giỏ hàng (Groceries)

Sinh bởi `apps/groceries/run_groceries.jl` ngày 2026-11-24 bằng `EclatFIM` (`v1`, seed = 42).

## 1. So sánh phương án biến đổi dữ liệu (Bảng B08)

| Phương án | N | m | L̄ | Mật độ ρ | Tập phổ biến (1%) | Luật (conf ≥ 0,3) | Thời gian (s) |
|---|---:|---:|---:|---:|---:|---:|---:|
| 169 mặt hàng gốc (chọn) | 9835 | 169 | 4.41 | 2.61% | 333 | 125 | 0.0256 |
| Gộp 12 nhóm hàng cấp cao | 9835 | 12 | 3.12 | 25.98% | 477 | 2232 | 0.0024 |

- Mật độ của bản 169 mặt hàng là **2.61%**, rất sát ngưỡng cân bằng `1/32 ≈ 3,125%` giữa `Vector` và `BitVector` của Eclat.
- Gộp thành 12 nhóm hàng làm mật độ tăng vọt lên **25.98%**, số tập phổ biến tăng mạnh nhưng luật trở nên quá chung chung, khó gợi ý xếp kệ cụ thể.

## 2. Khảo sát độ nhạy lưới ngưỡng

| minsup | σ_min | Tập phổ biến | minconf | Số luật | Lift lớn nhất |
|---|---:|---:|---:|---:|---:|
| 0.5% | 50 | 1001 | 0.2 | 893 | 5.212 |
| 0.5% | 50 | 1001 | 0.3 | 487 | 4.716 |
| 0.5% | 50 | 1001 | 0.5 | 120 | 3.691 |
| 1% | 99 | 333 | 0.2 | 234 | 3.295 |
| 1% | 99 | 333 | 0.3 | 125 | 3.295 |
| 1% | 99 | 333 | 0.5 | 15 | 3.03 |
| 2% | 197 | 122 | 0.2 | 73 | 2.842 |
| 2% | 197 | 122 | 0.3 | 37 | 2.842 |
| 2% | 197 | 122 | 0.5 | 1 | 2.007 |

- Chọn **minsup = 1%, minconf = 0.3** vì cho **125 luật** (nằm gọn trong vùng 50–300 luật), cân bằng giữa độ phủ và ý nghĩa kinh doanh.

## 3. Top-10 luật theo Lift (Bảng B09)

| # | Tiền đề (X) | Hệ quả (Y) | σ | Support | Confidence | Lift |
|---:|---|---|---:|---:|---:|---:|
| 1 | citrus fruit + other vegetables | root vegetables | 102 | 0.0104 | 0.3592 | 3.295 |
| 2 | other vegetables + tropical fruit | root vegetables | 121 | 0.0123 | 0.3428 | 3.145 |
| 3 | beef | root vegetables | 171 | 0.0174 | 0.3314 | 3.04 |
| 4 | citrus fruit + root vegetables | other vegetables | 102 | 0.0104 | 0.5862 | 3.03 |
| 5 | root vegetables + tropical fruit | other vegetables | 121 | 0.0123 | 0.5845 | 3.021 |
| 6 | other vegetables + whole milk | root vegetables | 228 | 0.0232 | 0.3098 | 2.842 |
| 7 | curd + whole milk | yogurt | 99 | 0.0101 | 0.3852 | 2.761 |
| 8 | rolls/buns + root vegetables | other vegetables | 120 | 0.0122 | 0.5021 | 2.595 |
| 9 | root vegetables + yogurt | other vegetables | 127 | 0.0129 | 0.5 | 2.584 |
| 10 | tropical fruit + whole milk | yogurt | 149 | 0.0151 | 0.3582 | 2.568 |

- **Vì sao xếp theo lift thay vì confidence:** mặt hàng `whole milk` xuất hiện trong **2513/9835 giỏ (25.55%)**, nên hầu hết các luật có confidence cao nhất đều có hệ quả là `whole milk` nhưng lift chỉ quanh 1,8–2,3:
  - `citrus fruit + root vegetables ⇒ other vegetables`: conf = 0.586, lift = 3.03
  - `root vegetables + tropical fruit ⇒ other vegetables`: conf = 0.585, lift = 3.021
  - `curd + yogurt ⇒ whole milk`: conf = 0.582, lift = 2.279
  - `butter + other vegetables ⇒ whole milk`: conf = 0.574, lift = 2.245
  - `root vegetables + tropical fruit ⇒ whole milk`: conf = 0.57, lift = 2.231

## 4. Độ ổn định khi chia 80/20 (Bảng B10, train=7868, test=1967)

| # | Luật (X ⇒ Y) | Train Lift | Test Lift | Chênh lệch | Train Conf | Test Conf |
|---:|---|---:|---:|---:|---:|---:|
| 1 | citrus fruit + other vegetables ⇒ root vegetables | 3.325 | 3.175 | -4.5% | 0.361 | 0.352 |
| 2 | other vegetables + tropical fruit ⇒ root vegetables | 3.242 | 2.734 | -15.7% | 0.352 | 0.303 |
| 3 | citrus fruit + root vegetables ⇒ other vegetables | 3.159 | 2.568 | -18.7% | 0.61 | 0.5 |
| 4 | beef ⇒ root vegetables | 3.093 | 2.831 | -8.5% | 0.336 | 0.314 |
| 5 | root vegetables + tropical fruit ⇒ other vegetables | 3.04 | 2.935 | -3.4% | 0.587 | 0.571 |
| 6 | whipped/sour cream + whole milk ⇒ root vegetables | 2.925 | 1.805 | -38.3% | 0.317 | 0.2 |
| 7 | other vegetables + yogurt ⇒ root vegetables | 2.864 | 2.203 | -23.1% | 0.311 | 0.244 |
| 8 | other vegetables + whole milk ⇒ root vegetables | 2.787 | 3.072 | 10.2% | 0.303 | 0.34 |
| 9 | other vegetables + whipped/sour cream ⇒ yogurt | 2.612 | 2.214 | -15.3% | 0.367 | 0.302 |
| 10 | rolls/buns + root vegetables ⇒ other vegetables | 2.588 | 2.628 | 1.5% | 0.5 | 0.512 |

- Có **10/10** luật giữ được `test_lift > 1.5` trên tập kiểm tra độc lập 20%.
