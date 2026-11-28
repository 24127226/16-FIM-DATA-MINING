# Application 2: image-to-transaction transformation schemes (Table B11)

Mined on 280 training images, minsup = 30%, itemsets of at most 4 visual words. Times are the minimum of 3 warmed-up mining runs. Accuracy is measured on a validation split (72 images held out from the training set); the test set is not used here.

| k | Encoding | m | L̄ | Density | Itemsets | v3 (vector) | v4 (bitset) | v6 (hybrid) | Val. itemset | Val. histogram |
|---|---|---|---|---|---|---|---|---|---|---|
| 100 | presence, all words | 100 | 56.0 | 56.0% | 48879 | 104.13 ms | 5.79 ms | 6.47 ms | 0.625 | 0.833 |
| 100 | presence, stop words removed | 25 | 9.4 | 37.6% | 34 | 0.10 ms | 0.02 ms | 0.07 ms | 0.667 | 0.833 |
| 100 | stop words removed, plus "occurs ≥ 2 times" items | 50 | 15.0 | 30.0% | 44 | 0.17 ms | 0.04 ms | 0.13 ms | 0.667 | 0.833 |
| 100 | stop words removed, word × image quadrant | 100 | 13.7 | 13.7% | 1 | 0.01 ms | 0.01 ms | 0.01 ms | 0.556 | 0.833 |
| 200 | presence, all words | 200 | 76.2 | 38.1% | 242 | 7.47 ms | 0.32 ms | 1.36 ms | 0.653 | 0.875 |
| 200 | presence, stop words removed | 190 | 71.0 | 37.4% | 171 | 5.41 ms | 0.30 ms | 1.18 ms | 0.667 | 0.875 |
| 200 | stop words removed, plus "occurs ≥ 2 times" items **(selected)** | 380 | 103.1 | 27.1% | 171 | 5.34 ms | 0.31 ms | 1.17 ms | 0.708 | 0.875 |
| 200 | stop words removed, word × image quadrant | 760 | 94.6 | 12.4% | 1 | 0.10 ms | 0.08 ms | 0.08 ms | 0.708 | 0.875 |
| 500 | presence, all words | 500 | 98.7 | 19.7% | 8 | 0.10 ms | 0.08 ms | 0.16 ms | 0.708 | 0.917 |
| 500 | presence, stop words removed | 500 | 98.7 | 19.7% | 8 | 0.07 ms | 0.06 ms | 0.11 ms | 0.708 | 0.917 |
| 500 | stop words removed, plus "occurs ≥ 2 times" items | 1000 | 126.7 | 12.7% | 8 | 0.09 ms | 0.08 ms | 0.23 ms | 0.694 | 0.917 |
| 500 | stop words removed, word × image quadrant | 1995 | 115.4 | 5.8% | 0 | 0.04 ms | 0.04 ms | 0.04 ms | 0.000 | 0.917 |

**Selected scheme:** k = 200, stop words removed, plus "occurs ≥ 2 times" items. Rule: highest validation accuracy with itemset features only; ties go to the smaller k.
