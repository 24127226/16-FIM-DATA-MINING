# E7: biểu diễn tidset theo mật độ (giả thuyết H2)

Sinh bởi `scripts/bench_density.jl`. Tỉ số > 1 nghĩa là bitset (v4) có lợi hơn vector (v3).

| Nguồn | Bộ | minsup | Mật độ ρ | Thời gian v3 / v4 | Bộ nhớ tidset v3 / v4 | Bản lai v6 so với bản tốt hơn trong v3, v4 |
|---|---|---|---|---|---|---|
| tong_hop | uniform_p0.003 | σ=1 | 0.0029 | 2.05 | 0.066 | 0.77× |
| tong_hop | uniform_p0.006 | σ=2 | 0.0060 | 2.12 | 0.125 | 1.55× |
| tong_hop | uniform_p0.01 | σ=4 | 0.0100 | 2.08 | 0.186 | 1.90× |
| tong_hop | uniform_p0.02 | σ=16 | 0.0199 | 3.07 | 0.359 | 2.92× |
| tong_hop | uniform_p0.03125 | σ=40 | 0.0310 | 4.19 | 0.574 | 4.75× |
| tong_hop | uniform_p0.05 | σ=101 | 0.0496 | 5.94 | 0.859 | 1.99× |
| tong_hop | uniform_p0.1 | σ=401 | 0.0998 | 12.04 | 1.774 | 3.68× |
| tong_hop | uniform_p0.2 | σ=1601 | 0.1996 | 21.84 | 3.863 | 2.76× |
| tong_hop | uniform_p0.4 | σ=6401 | 0.3998 | 39.41 | 8.990 | 3.40× |
| benchmark | chess | 80% | 0.9339 | 44.21 | 27.769 | 1.83× |
| benchmark | chess | 65% | 0.8633 | 37.13 | 24.640 | 1.05× |
| benchmark | chess | 50% | 0.8050 | 29.43 | 20.573 | 1.01× |
| benchmark | mushroom | 30% | 0.5541 | 27.11 | 13.706 | 3.05× |
| benchmark | mushroom | 15% | 0.4189 | 24.03 | 9.017 | 1.34× |
| benchmark | mushroom | 5% | 0.3051 | 8.74 | 6.332 | 1.00× |
| benchmark | accidents | 80% | 0.9069 | 3.16 | 27.778 | 2.65× |
| benchmark | accidents | 65% | 0.8390 | 12.67 | 24.363 | 3.10× |
| benchmark | accidents | 50% | 0.7764 | 47.14 | 20.607 | 3.24× |
| benchmark | retail | 1% | 0.0383 | 2.00 | 1.279 | 1.04× |
| benchmark | retail | 0.1% | 0.0036 | 0.84 | 0.119 | 0.06× |
| benchmark | retail | 0.01% | 0.0011 | 0.23 | 0.037 | 0.06× |
| benchmark | T10I4D100K | 1% | 0.0212 | 7.14 | 0.676 | 0.38× |
| benchmark | T10I4D100K | 0.1% | 0.0126 | 6.49 | 0.386 | 0.79× |
| benchmark | T10I4D100K | 0.01% | 0.0117 | 0.56 | 0.203 | 0.54× |
| ung_dung_1 | groceries | 2% | 0.0620 | 10.91 | 1.887 | 2.33× |
| ung_dung_1 | groceries | 1% | 0.0463 | 15.03 | 1.371 | 2.48× |
| ung_dung_1 | groceries | 0.5% | 0.0358 | 13.19 | 1.022 | 2.13× |
| ung_dung_2 | k100_count2 | 30% | 0.4015 | 4.46 | 10.993 | 3.19× |
| ung_dung_2 | k100_presence | 30% | 0.4239 | 4.11 | 11.477 | 2.73× |
| ung_dung_2 | k100_presence_all | 30% | 0.5820 | 13.78 | 13.131 | 1.09× |
| ung_dung_2 | k100_quadrant | 30% | 0.3286 | 0.85 | 9.200 | 1.10× |
| ung_dung_2 | k200_count2 | 30% | 0.4071 | 15.93 | 11.342 | 3.88× |
| ung_dung_2 | k200_presence | 30% | 0.4071 | 16.86 | 11.342 | 3.93× |
| ung_dung_2 | k200_presence_all | 30% | 0.4138 | 11.21 | 11.450 | 2.19× |
| ung_dung_2 | k200_quadrant | 30% | 0.3000 | 0.84 | 8.400 | 1.17× |
| ung_dung_2 | k500_count2 | 30% | 0.3237 | 0.95 | 9.062 | 1.88× |
| ung_dung_2 | k500_presence | 30% | 0.3237 | 0.93 | 9.062 | 2.08× |
| ung_dung_2 | k500_presence_all | 30% | 0.3237 | 0.99 | 9.062 | 1.95× |
| ung_dung_2 | k500_quadrant | 30% | NaN | 1.01 | 0.000 | 1.00× |

**Điểm cân bằng ước lượng trên dữ liệu tổng hợp:** về thời gian ρ ≈ NaN; về bộ nhớ ρ ≈ 0.0575 (lý thuyết: 1/32 = 0,03125).
