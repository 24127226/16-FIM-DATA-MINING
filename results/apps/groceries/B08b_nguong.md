# Ứng dụng 1: khảo sát ngưỡng

N = 9835 hóa đơn. Mỗi ô: số tập phổ biến / số luật (thời gian khai thác).

| minsup \ minconf | 0.2 | 0.3 | 0.5 |
|---|---|---|---|
| 0.5% (σ = 50) | 1001 / 893 (3.4 ms) | 1001 / 487 (3.5 ms) | 1001 / 120 (3.1 ms) |
| 1% (σ = 99) | 333 / 234 (2.5 ms) | 333 / 125 (2.2 ms) | 333 / 15 (1.8 ms) |
| 2% (σ = 197) | 122 / 73 (1.4 ms) | 122 / 37 (1.4 ms) | 122 / 1 (1.4 ms) |

**Ngưỡng chọn:** minsup = 0.5%, minconf = 0.5. Quy tắc: trong các cặp cho 50–300 luật (đủ để phân tích, không quá nhiều để đọc), lấy minsup nhỏ nhất để phủ được nhiều mặt hàng nhất; hòa thì lấy minconf lớn nhất.
