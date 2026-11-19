---
pretty_name: Frequent itemset mining benchmarks (SPMF format)
license: other
tags:
- frequent-itemset-mining
- association-rules
- market-basket-analysis
- spmf
- fimi
size_categories:
- 100K<n<1M
---

# Frequent itemset mining benchmarks (SPMF format)

Bản lưu trữ dữ liệu dùng trong đồ án *Khai thác tập phổ biến bằng Eclat (Julia)* (môn Khai thác dữ liệu và ứng dụng, HCMUS). Mục đích: notebook demo trên Google Colab tải được dữ liệu ổn định, không cần đăng nhập.

> **Ghi chú cho nhóm (xóa đoạn này trước khi tải lên):** tạo một dataset **public** trên Hugging Face, tải lên các file trong bảng dưới (lấy từ `data/` sau khi chạy `julia --project=. scripts/fetch_data.jl all`) cùng file README này. Sau đó điền link dạng `https://huggingface.co/datasets/<tài-khoản>/<tên-dataset>/resolve/main` vào hằng số `HF_DATA_BASE` trong `scripts/fetch_data.jl` và vào README của repo, rồi kiểm tra bằng trình duyệt ẩn danh rằng link tải được khi không đăng nhập.

## Nội dung

Mọi file benchmark theo định dạng SPMF: mỗi dòng một giao dịch, các item là số nguyên cách nhau đúng một dấu cách. Thống kê do nhóm tự đo lại (N: số giao dịch, m: số item phân biệt, L̄: độ dài giao dịch trung bình).

| File | N | m | L̄ | Nguồn | SHA-256 |
|---|---|---|---|---|---|
| `chess.txt` | 3.196 | 75 | 37,00 | SPMF / FIMI, gốc từ UCI *Chess (King-Rook vs. King-Pawn)* | `a12ea887df58a396709430af5bf0a9a32d1f6eba8e7c13dd41f28b98572c5db2` |
| `mushroom.txt` | 8.124 | 119 | 23,00 | FIMI (`mushroom.dat`, đã bỏ dấu cách cuối dòng), gốc từ UCI *Mushroom* | `06206c73983251a9488414c4379a030e836bbeb6fe9eff1b5624a0193a811640` |
| `retail.txt` | 88.162 | 16.470 | 10,31 | SPMF / FIMI; giỏ hàng ẩn danh của một siêu thị ở Bỉ (Brijs và cộng sự, 1999) | `732c26de19888cb570d3fbb97e47206a9b1c0ce064f85dc1403314ba38f04eaa` |
| `accidents.txt` | 340.183 | 468 | 33,81 | SPMF / FIMI; dữ liệu tai nạn giao thông ẩn danh ở Bỉ (Geurts và cộng sự, 2003) | `8c2275550966e3cb4b6066f2bb168489a9566c500af559fa3925f1b11d97f0cd` |
| `T10I4D100K.txt` | 100.000 | 870 | 10,10 | SPMF / FIMI; dữ liệu tổng hợp từ bộ sinh IBM Quest (Agrawal và Srikant, 1994) | `949983f61aa976d1b774474fadd31c5f15775b24728a5e7c8b79801822ab3f89` |
| `groceries.csv` | 9.835 | 169 | 4,41 | Groceries của gói R `arules` (Hahsler và cộng sự, 2005), bản CSV trong repo *Machine-Learning-with-R-datasets* | `ff1be892fd6b9b57d1a7bc50de067798963dda607619645988b21789bf23ae3b` |

Ứng dụng 2 dùng Caltech-101 (Fei-Fei và cộng sự, 2004; giấy phép CC BY 4.0), tải trực tiếp từ [CaltechDATA](https://data.caltech.edu/records/mzrjq-6wc02). Nếu muốn lưu thêm bản sao ở đây, tải lên `caltech-101.zip` nguyên gốc (SHA-256 `331234750fc7f77520e50d9565e8b6907b03565e30320da1401130db08c61f91`) và giữ nguyên ghi công.

## Cách dùng

```
julia --project=. scripts/fetch_data.jl benchmark      # hoặc: groceries, caltech, all
```

Script trong repo thử link Hugging Face trước, sau đó đến nguồn gốc, và kiểm tra SHA-256 của từng file.

## Ghi công và điều khoản

Nhóm chỉ lưu lại bản sao để tái lập thí nghiệm; mỗi file giữ điều khoản sử dụng của nguồn gốc. Khi dùng, hãy trích dẫn nguồn gốc:

- Kho FIMI: B. Goethals, M. J. Zaki (eds.), *Proceedings of the IEEE ICDM Workshop on Frequent Itemset Mining Implementations (FIMI'03)*, 2003. http://fimi.uantwerpen.be/data/
- Thư viện SPMF: P. Fournier-Viger và cộng sự, "SPMF: a Java open-source pattern mining library", *JMLR* 15, 2014.
- Chess, Mushroom: UCI Machine Learning Repository (CC BY 4.0).
- Retail: T. Brijs, G. Swinnen, K. Vanhoof, G. Wets, "Using association rules for product assortment decisions: a case study", *KDD*, 1999.
- Accidents: K. Geurts, G. Wets, T. Brijs, K. Vanhoof, "Profiling high frequency accident locations using association rules", *Transportation Research Record* 1840, 2003.
- T10I4D100K: R. Agrawal, R. Srikant, "Fast algorithms for mining association rules", *VLDB*, 1994.
- Groceries: M. Hahsler, B. Grün, K. Hornik, "arules: a computational environment for mining association rules and frequent item sets", *Journal of Statistical Software* 14(15), 2005.
