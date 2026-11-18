# Dữ liệu nhỏ (toy)

Các CSDL nhỏ, có commit trong repo, dùng để kiểm thử nhanh và chạy tay.

| File | Nguồn | N | Ghi chú |
|---|---|---|---|
| `pasquier99.txt` | Ví dụ `contextPasquier99.txt` trong tài liệu SPMF | 5 | minsup 40% (2 giao dịch) cho đúng **15** tập phổ biến |
| `bookstore.txt` | Ví dụ hiệu sách, Fig. 1 trong bài báo của Zaki (2000) | 6 | minsup 50% (3 giao dịch) cho đúng **19** tập phổ biến; 2 tập tối đại `1 2 4 5` (ACTW) và `2 3 5` (CDW) |

Mã item của `bookstore.txt` theo tên tác giả trong bài báo:

| Mã | Tác giả |
|---|---|
| 1 | A |
| 2 | C |
| 3 | D |
| 4 | T |
| 5 | W |

Các ca biên (giao dịch giống hệt nhau, mã item lớn và rời rạc, dòng chú thích…) được sinh trực tiếp trong `test/` để không phải lưu thêm file.
