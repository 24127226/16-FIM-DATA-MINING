# Hành vi của SPMF (kiểm chứng bằng thí nghiệm hộp đen)

Sinh bởi `scripts/verify_spmf_behavior.jl`. Phiên bản SPMF: xem `results/ENV.md`.

## 1. Đổi minsup sang số đếm

Mỗi ca dùng một CSDL N giao dịch, trong đó item 1 xuất hiện đúng k lần. Ngưỡng thật của SPMF
là số k nhỏ nhất để item 1 được coi là phổ biến.

| N | minsup | Giá trị toán học đúng | `ceil((p/100)·N)` bằng Float64 | Ngưỡng SPMF quan sát được | Khớp quy tắc của nhóm? |
|---|---|---|---|---|---|
| 5 | `40%` | 2 | 2 | 2 | ✅ |
| 5 | `30%` | 2 | 2 | 2 | ✅ |
| 10 | `70%` | 7 | 7 | 7 | ✅ |
| 25 | `28%` | 7 | 8 | 8 | ✅ |
| 50 | `14%` | 7 | 8 | 8 | ✅ |
| 40 | `17.5%` | 7 | 7 | 7 | ✅ |
| 20 | `35%` | 7 | 7 | 7 | ✅ |
| 100 | `7%` | 7 | 8 | 8 | ✅ |
| 10 | `0.7` | 7 | 7 | 7 | ✅ |
| 3196 | `50%` | 1598 | 1598 | 1598 | ✅ |

**Kết luận:** SPMF dùng đúng công thức `σ_min = ceil(minsup × N)` tính bằng số thực Float64, với `"p%"` được đổi thành `p / 100`, còn chuỗi không có `%` được hiểu là tỉ lệ. Kết quả **có thể lệch** khỏi giá trị toán học đúng (ví dụ 28% của 25 cho ngưỡng 8, không phải 7). Muốn khớp 100% thì code của nhóm phải tính **y hệt**, và hai bên phải nhận **cùng một chuỗi minsup**.

## 2. Đếm số giao dịch và định dạng input

| Ca | Nội dung thử | SPMF chạy được? | N SPMF đếm | Số tập (minsup 40%) |
|---|---|---|---|---|
| Chuẩn (Pasquier99) | 5 dòng, cách nhau một dấu cách | ✅ | 5 | 15 |
| Dòng rỗng và chú thích | chèn dòng rỗng, `#…`, `%…`, `@…` | ✅ | 5 | 15 |
| Item 0 | thay item 1 bằng 0 | ✅ | 5 | 15 |
| Chưa sắp xếp | `3 1 4`, `5 2` | ✅ | 5 | 15 |
| Item trùng | `2 3 5 5` | ❌ lỗi | — | — |
| Dấu tab | `2 3 5<TAB>` | ❌ lỗi | — | — |
| Hai dấu cách liền nhau | `2  3 5` | ❌ lỗi | — | — |
| Dấu cách đầu dòng | ` 1 3 4` | ❌ lỗi | — | — |
| Dấu cách cuối dòng | `1 3 4 ` | ✅ | 5 | 15 |
| Xuống dòng kiểu Windows | CRLF | ✅ | 5 | 15 |

**Kết luận cho bộ đọc của nhóm (`read_spmf`):**

- Bỏ qua dòng rỗng và dòng bắt đầu bằng `#`, `%`, `@`; **N là số dòng còn lại**, đúng như SPMF đếm.
- Item 0 hợp lệ (dù tài liệu SPMF ghi "positive integer").
- Thứ tự item trong dòng không ảnh hưởng kết quả của Eclat; bộ đọc của nhóm vẫn sắp xếp lại.
- SPMF **báo lỗi** khi có item trùng, dấu tab, hai dấu cách liền nhau hoặc dấu cách đầu dòng. Bộ đọc của nhóm dễ tính hơn (chấp nhận mọi khoảng trắng, tự bỏ item trùng), nhưng **file dữ liệu dùng để so với SPMF phải sạch**: các script chuyển đổi dữ liệu luôn ghi đúng một dấu cách giữa các item.

## 3. Mã item rất lớn và rời rạc

CSDL 5 giao dịch, minsup 40%, mã item lớn nhất 1.000.000 (đáp án đúng: 8 tập phổ biến; ca kiểm thử "Mã item rất lớn và rời rạc" trong `test/test_correctness.jl`).

| Thuật toán SPMF | Chạy được? | Số tập | Dòng lỗi đầu tiên | Dòng đầu của stack trace |
|---|---|---|---|---|
| `Eclat` | ❌ error | — | `Exception in thread "main" java.lang.OutOfMemoryError: Java heap space` | `at ca.pfv.spmf.datastructures.triangularmatrix.TriangularMatrix.<init>(TriangularMatrix.java:64)` |
| `Eclat_bitset` | ❌ error | — | `Exception in thread "main" java.lang.OutOfMemoryError: Java heap space` | `at ca.pfv.spmf.datastructures.triangularmatrix.TriangularMatrix.<init>(TriangularMatrix.java:64)` |

Dòng lỗi chỉ ghi lại thông báo SPMF in ra màn hình (kiểm chứng hộp đen); nhóm không đọc mã nguồn SPMF. Bộ đọc của nhóm đổi mã gốc về 1..m nên không bị ảnh hưởng bởi độ lớn của mã item.
