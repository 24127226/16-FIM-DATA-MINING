# Ứng dụng 1: so sánh với phương án bỏ hóa đơn 1 món

| Phương án | N | σ_min | Số tập | Số luật |
|---|---|---|---|---|
| Mỗi hóa đơn là một giao dịch | 9835 | 50 | 1001 | 120 |
| Bỏ hóa đơn 1 món | 7676 | 39 | 1473 | 224 |

4/10 luật top-10 theo lift trùng nhau giữa hai phương án. Top-10 của phương án bỏ hóa đơn 1 món:

| # | Luật | Số hóa đơn | Support | Confidence | Lift |
|---|---|---|---|---|---|
| 1 | {herbs, whole milk} ⇒ {root vegetables} | 41 | 0.53% | 0.539 | 3.955 |
| 2 | {curd, tropical fruit, whole milk} ⇒ {yogurt} | 39 | 0.51% | 0.609 | 3.512 |
| 3 | {citrus fruit, root vegetables, tropical fruit} ⇒ {other vegetables} | 44 | 0.57% | 0.786 | 3.276 |
| 4 | {tropical fruit, whipped/sour cream, whole milk} ⇒ {yogurt} | 43 | 0.56% | 0.551 | 3.177 |
| 5 | {curd, tropical fruit} ⇒ {yogurt} | 52 | 0.68% | 0.515 | 2.967 |
| 6 | {citrus fruit, root vegetables, whole milk} ⇒ {other vegetables} | 57 | 0.74% | 0.633 | 2.641 |
| 7 | {pip fruit, root vegetables, whole milk} ⇒ {other vegetables} | 54 | 0.70% | 0.614 | 2.559 |
| 8 | {root vegetables, tropical fruit, yogurt} ⇒ {other vegetables} | 49 | 0.64% | 0.613 | 2.554 |
| 9 | {fruit/vegetable juice, root vegetables, whole milk} ⇒ {other vegetables} | 39 | 0.51% | 0.609 | 2.541 |
| 10 | {pip fruit, whipped/sour cream} ⇒ {other vegetables} | 55 | 0.72% | 0.604 | 2.520 |
