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

