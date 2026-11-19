# Ứng dụng 1: top-10 luật theo confidence (để so với xếp theo lift)

| # | Luật | Số hóa đơn | Support | Confidence | Lift |
|---|---|---|---|---|---|
| 1 | {root vegetables, tropical fruit, yogurt} ⇒ {whole milk} | 56 | 0.57% | 0.700 | 2.740 |
| 2 | {other vegetables, pip fruit, root vegetables} ⇒ {whole milk} | 54 | 0.55% | 0.675 | 2.642 |
| 3 | {butter, whipped/sour cream} ⇒ {whole milk} | 66 | 0.67% | 0.660 | 2.583 |
| 4 | {pip fruit, whipped/sour cream} ⇒ {whole milk} | 59 | 0.60% | 0.648 | 2.537 |
| 5 | {butter, yogurt} ⇒ {whole milk} | 92 | 0.94% | 0.639 | 2.500 |
| 6 | {butter, root vegetables} ⇒ {whole milk} | 81 | 0.82% | 0.638 | 2.496 |
| 7 | {curd, tropical fruit} ⇒ {whole milk} | 64 | 0.65% | 0.634 | 2.480 |
| 8 | {citrus fruit, root vegetables, whole milk} ⇒ {other vegetables} | 57 | 0.58% | 0.633 | 3.273 |
| 9 | {other vegetables, pip fruit, yogurt} ⇒ {whole milk} | 50 | 0.51% | 0.625 | 2.446 |
| 10 | {domestic eggs, pip fruit} ⇒ {whole milk} | 53 | 0.54% | 0.624 | 2.440 |

9/10 luật có vế phải chứa "whole milk" (mặt hàng có mặt trong 25.55% hóa đơn). Confidence cao chủ yếu vì vế phải vốn đã rất phổ biến; lift chia cho support của vế phải nên loại được hiệu ứng này.
