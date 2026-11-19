# Ứng dụng 2: các phương án biến đổi ảnh thành giao dịch

Khai thác trên 280 ảnh huấn luyện, minsup = 30%, tập tối đa 4 visual word. Thời gian là thời gian khai thác nhỏ nhất trong 3 lần (đã khởi động). Độ chính xác đo trên tập validation (72 ảnh tách từ tập huấn luyện), không dùng tập kiểm tra.

| k | Cách mã hóa | m | L̄ | Mật độ | Số tập | v3 (vector) | v4 (bitset) | v6 (lai) | Val. itemset | Val. histogram |
|---|---|---|---|---|---|---|---|---|---|---|
| 100 | có mặt, giữ mọi từ | 100 | 56.0 | 56.0% | 48879 | 96.67 ms | 6.40 ms | 6.28 ms | 0.625 | 0.833 |
| 100 | có mặt, bỏ từ quá phổ biến | 25 | 9.4 | 37.6% | 34 | 0.13 ms | 0.04 ms | 0.15 ms | 0.667 | 0.833 |
| 100 | bỏ từ quá phổ biến, thêm "xuất hiện ≥ 2 lần" | 50 | 15.0 | 30.0% | 44 | 0.17 ms | 0.05 ms | 0.14 ms | 0.667 | 0.833 |
| 100 | bỏ từ quá phổ biến, từ kèm góc phần tư | 100 | 13.7 | 13.7% | 1 | 0.01 ms | 0.01 ms | 0.01 ms | 0.556 | 0.833 |
| 200 | có mặt, giữ mọi từ | 200 | 76.2 | 38.1% | 242 | 7.47 ms | 0.41 ms | 2.52 ms | 0.653 | 0.875 |
| 200 | có mặt, bỏ từ quá phổ biến | 190 | 71.0 | 37.4% | 171 | 7.15 ms | 0.32 ms | 1.29 ms | 0.667 | 0.875 |
| 200 | bỏ từ quá phổ biến, thêm "xuất hiện ≥ 2 lần" **(chọn)** | 380 | 103.1 | 27.1% | 171 | 5.72 ms | 0.31 ms | 1.13 ms | 0.708 | 0.875 |
| 200 | bỏ từ quá phổ biến, từ kèm góc phần tư | 760 | 94.6 | 12.4% | 1 | 0.09 ms | 0.08 ms | 0.07 ms | 0.708 | 0.875 |
| 500 | có mặt, giữ mọi từ | 500 | 98.7 | 19.7% | 8 | 0.07 ms | 0.06 ms | 0.11 ms | 0.708 | 0.917 |
| 500 | có mặt, bỏ từ quá phổ biến | 500 | 98.7 | 19.7% | 8 | 0.11 ms | 0.09 ms | 0.17 ms | 0.708 | 0.917 |
| 500 | bỏ từ quá phổ biến, thêm "xuất hiện ≥ 2 lần" | 1000 | 126.7 | 12.7% | 8 | 0.15 ms | 0.13 ms | 0.22 ms | 0.694 | 0.917 |
| 500 | bỏ từ quá phổ biến, từ kèm góc phần tư | 1995 | 115.4 | 5.8% | 0 | 0.03 ms | 0.03 ms | 0.02 ms | 0.000 | 0.917 |

**Phương án chọn:** k = 200, bỏ từ quá phổ biến, thêm "xuất hiện ≥ 2 lần". Quy tắc chọn: độ chính xác validation cao nhất khi chỉ dùng đặc trưng itemset; hòa thì lấy k nhỏ hơn.
