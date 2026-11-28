# Kết quả Ứng dụng 1: Phân tích giỏ hàng (Groceries)

Sinh bởi `apps/groceries/run_groceries.jl` ngày 2026-11-28 bằng `EclatFIM` (`v6`, seed = 42).

## 1. So sánh phương án biến đổi dữ liệu (Bảng B08)

| Phương án | N | m | L̄ | Mật độ ρ | Tập phổ biến (1%) | Luật (conf ≥ 0,3) | Thời gian (s) |
|---|---:|---:|---:|---:|---:|---:|---:|
| 169 mặt hàng gốc (chọn) | 9835 | 169 | 4.41 | 2.61% | 333 | 125 | 0.0012 |
| Gộp 12 nhóm hàng cấp cao | 9835 | 12 | 3.12 | 25.98% | 477 | 2232 | 0.0008 |

- Phương án 169 mặt hàng gốc có mật độ **2.61%**, tiệm cận ngưỡng cân bằng lý thuyết `1/32 ≈ 3,125%` giữa biểu diễn `Vector` và `BitVector` của Eclat.
- Phương án gom 12 nhóm hàng làm mật độ tăng lên **25.98%**, dẫn đến gia tăng mạnh số tập phổ biến và số luật nhưng làm giảm tính cụ thể của luật.

## 2. Khảo sát độ nhạy trên lưới ngưỡng

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

- Cặp ngưỡng **minsup = 1%, minconf = 0.3** được lựa chọn vì tạo ra **125 luật** (thuộc vùng mục tiêu 50–300 luật), cân bằng giữa độ bao phủ và độ tin cậy diễn giải.

## 3. Mười luật kết hợp dẫn đầu theo độ nâng (Bảng B09)

| Hạng | Tiền đề (X) | Hệ quả (Y) | σ | Support | Confidence | Lift |
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

- **Phân tích tiêu chí xếp hạng:** mặt hàng `whole milk` xuất hiện trong **2513/9835 hóa đơn (25.55%)**, khiến các luật đạt confidence cao nhất chủ yếu mang hệ quả `whole milk` nhưng chỉ đạt lift trung bình (1,8–2,3):
  - `citrus fruit + root vegetables ⇒ other vegetables`: conf = 0.586, lift = 3.03
  - `root vegetables + tropical fruit ⇒ other vegetables`: conf = 0.585, lift = 3.021
  - `curd + yogurt ⇒ whole milk`: conf = 0.582, lift = 2.279
  - `butter + other vegetables ⇒ whole milk`: conf = 0.574, lift = 2.245
  - `root vegetables + tropical fruit ⇒ whole milk`: conf = 0.57, lift = 2.231

## 4. Đánh giá độ ổn định trên phép chia 80/20 (Bảng B10, train=7868, test=1967)

| Hạng | Luật (X ⇒ Y) | Train Lift | Test Lift | Biến thiên | Train Conf | Test Conf |
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

- Toàn bộ **10/10** luật duy trì `test_lift > 1,5` trên tập kiểm tra độc lập 20%.
