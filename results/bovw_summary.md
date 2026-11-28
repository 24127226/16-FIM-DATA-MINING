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

# Application 2: discriminative visual-word itemsets per class (Table B12)

Scheme: k = 200, stop words removed, plus "occurs ≥ 2 times" items. Each class is mined separately on its training images (minsup = 30% of the class, itemsets of 2–3 words), ranked by growth rate GR = s_class / s_other (∞: never occurs in another class, a "jumping emerging pattern"). Notation `w×2`: visual word w occurs at least twice in the image (item code 200 + w).

## airplanes (3089 frequent itemsets in the class)

| # | Visual words | s (this class) | s (other classes) | GR |
|---|---|---|---|---|
| 1 | 31, 41, 146 | 0.36 | 0.000 | ∞ |
| 2 | 31, 146, 171 | 0.36 | 0.000 | ∞ |
| 3 | 118, 146, 146×2 | 0.36 | 0.000 | ∞ |
| 4 | 118, 146×2 | 0.36 | 0.000 | ∞ |
| 5 | 41, 101, 118×2 | 0.33 | 0.000 | ∞ |

## Motorbikes (13134 frequent itemsets in the class)

| # | Visual words | s (this class) | s (other classes) | GR |
|---|---|---|---|---|
| 1 | 63, 139, 192 | 0.31 | 0.005 | 66.0 |
| 2 | 12, 57, 192×2 | 0.30 | 0.005 | 63.0 |
| 3 | 120, 189, 192 | 0.37 | 0.010 | 39.0 |
| 4 | 2, 20, 182 | 0.31 | 0.010 | 33.0 |
| 5 | 29, 120, 137 | 0.31 | 0.010 | 33.0 |

## Faces_easy (4881 frequent itemsets in the class)

| # | Visual words | s (this class) | s (other classes) | GR |
|---|---|---|---|---|
| 1 | 56, 73, 113 | 0.36 | 0.000 | ∞ |
| 2 | 87, 126, 167 | 0.36 | 0.000 | ∞ |
| 3 | 22, 166, 187 | 0.34 | 0.000 | ∞ |
| 4 | 59, 110, 110×2 | 0.34 | 0.000 | ∞ |
| 5 | 59, 110×2 | 0.34 | 0.000 | ∞ |

## watch (6645 frequent itemsets in the class)

| # | Visual words | s (this class) | s (other classes) | GR |
|---|---|---|---|---|
| 1 | 44, 72, 191×2 | 0.30 | 0.010 | 31.5 |
| 2 | 15, 74, 129×2 | 0.31 | 0.014 | 22.0 |
| 3 | 72, 115, 164×2 | 0.30 | 0.014 | 21.0 |
| 4 | 72, 191, 44×2 | 0.30 | 0.014 | 21.0 |
| 5 | 23, 72, 164×2 | 0.33 | 0.019 | 17.2 |


# Application 2: frequent visual patterns as classifier features (Table B13)

Multinomial logistic regression (own implementation), 280 training images, 120 test images, 4 classes. Discriminative patterns are mined on training images only.

| Features | Dimensions | Test accuracy |
|---|---|---|
| Histogram bag of visual words (k = 200) | 200 | 0.858 |
| Discriminative itemsets (20 per class) | 80 | 0.758 |
| Both combined | 280 | 0.867 |

Confusion matrix of the itemset features (rows: true class, columns: predicted class; order airplanes, Motorbikes, Faces_easy, watch):

| | airplanes | Motorbikes | Faces_easy | watch |
|---|---|---|---|---|
| airplanes | 29 | 1 | 0 | 0 |
| Motorbikes | 3 | 22 | 1 | 4 |
| Faces_easy | 2 | 2 | 24 | 2 |
| watch | 3 | 7 | 4 | 16 |
