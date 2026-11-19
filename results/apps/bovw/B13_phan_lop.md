# Ứng dụng 2: dùng mẫu trực quan phổ biến làm đặc trưng cho bộ phân lớp

Hồi quy logistic đa lớp (tự viết), 280 ảnh huấn luyện, 120 ảnh kiểm tra, 4 lớp. Mẫu đặc trưng chỉ được tìm trên ảnh huấn luyện.

| Đặc trưng | Số chiều | Độ chính xác (kiểm tra) |
|---|---|---|
| Histogram bag of visual words (k = 200) | 200 | 0.858 |
| Itemset đặc trưng (20 tập/lớp) | 80 | 0.758 |
| Kết hợp hai loại | 280 | 0.867 |

Ma trận nhầm lẫn của đặc trưng itemset (hàng: lớp thật, cột: lớp dự đoán; thứ tự airplanes, Motorbikes, Faces_easy, watch):

| | airplanes | Motorbikes | Faces_easy | watch |
|---|---|---|---|---|
| airplanes | 29 | 1 | 0 | 0 |
| Motorbikes | 3 | 22 | 1 | 4 |
| Faces_easy | 2 | 2 | 24 | 2 |
| watch | 3 | 7 | 4 | 16 |
