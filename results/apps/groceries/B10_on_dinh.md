# Ứng dụng 1: độ ổn định của luật (80% huấn luyện / 20% kiểm tra, seed = 42)

Luật tìm trên 7868 hóa đơn huấn luyện; confidence và lift tính lại trên 1967 hóa đơn kiểm tra.

| # | Luật | Conf. (huấn luyện) | Conf. (kiểm tra) | Lift (huấn luyện) | Lift (kiểm tra) | Hóa đơn chứa luật (kiểm tra) |
|---|---|---|---|---|---|---|
| 1 | {root vegetables, tropical fruit, whole milk} ⇒ {yogurt} | 0.500 | 0.350 | 3.563 | 2.569 | 7 |
| 2 | {citrus fruit, root vegetables, whole milk} ⇒ {other vegetables} | 0.649 | 0.562 | 3.358 | 2.889 | 9 |
| 3 | {pip fruit, root vegetables, whole milk} ⇒ {other vegetables} | 0.634 | 0.529 | 3.281 | 2.719 | 9 |
| 4 | {root vegetables, tropical fruit, yogurt} ⇒ {other vegetables} | 0.616 | 0.571 | 3.191 | 2.935 | 4 |
| 5 | {citrus fruit, root vegetables} ⇒ {other vegetables} | 0.610 | 0.500 | 3.159 | 2.568 | 19 |
| 6 | {root vegetables, tropical fruit, whole milk} ⇒ {other vegetables} | 0.592 | 0.550 | 3.064 | 2.825 | 11 |
| 7 | {onions, root vegetables} ⇒ {other vegetables} | 0.589 | 0.650 | 3.049 | 3.338 | 13 |
| 8 | {root vegetables, tropical fruit} ⇒ {other vegetables} | 0.587 | 0.571 | 3.040 | 2.935 | 20 |
| 9 | {fruit/vegetable juice, root vegetables} ⇒ {other vegetables} | 0.583 | 0.409 | 3.020 | 2.101 | 9 |
| 10 | {butter, whipped/sour cream} ⇒ {other vegetables} | 0.583 | 0.536 | 3.020 | 2.751 | 15 |

Trên toàn bộ 127 luật tìm được ở tập huấn luyện: 127 luật (100.00%) vẫn có lift > 1 trên tập kiểm tra.
7/10 luật trong top-10 (huấn luyện) trùng với top-10 trên toàn bộ dữ liệu.
