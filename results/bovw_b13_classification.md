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
