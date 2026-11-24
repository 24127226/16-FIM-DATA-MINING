# Dữ liệu benchmark

Các file `*.txt` trong thư mục này **không commit** lên GitHub (xem `.gitignore`). Tải lại bằng:

```
julia --project=. scripts/fetch_data.jl benchmark
```

Script tự kiểm tra SHA-256 của từng file và mặc định ưu tiên tải từ bộ dữ liệu công khai của nhóm trên Hugging Face ([cuongnguyen0794/16-fim-data-mining](https://huggingface.co/datasets/cuongnguyen0794/16-fim-data-mining)), sau đó mới lùi về nguồn gốc nếu cần. Có thể ghi đè nguồn tải qua biến môi trường `FIM_DATA_BASE`.

## Nguồn và thống kê

Thống kê dưới đây do nhóm **tự đo lại** trên chính các file này (17/11/2026), đối chiếu với bảng trong đề.

| File | N | m | L̄ | Bảng của đề (N / m / L̄) | Nguồn | SHA-256 |
|---|---|---|---|---|---|---|
| `chess.txt` | 3.196 | 75 | 37,00 | 3.196 / 75 / 37,0 ✅ | [SPMF](https://www.philippe-fournier-viger.com/spmf/publicdatasets/chess.txt) | `a12ea887df58a396709430af5bf0a9a32d1f6eba8e7c13dd41f28b98572c5db2` |
| `mushroom.txt` | 8.124 | 119 | 23,00 | 8.124 / 119 / 23,0 ✅ | [FIMI](https://fimi.uantwerpen.be/data/mushroom.dat), đã bỏ dấu cách cuối dòng | `06206c73983251a9488414c4379a030e836bbeb6fe9eff1b5624a0193a811640` |
| `retail.txt` | 88.162 | 16.470 | 10,31 | 88.162 / 16.47(0) / 10,3 ✅ | [SPMF](https://www.philippe-fournier-viger.com/spmf/publicdatasets/retail.txt) | `732c26de19888cb570d3fbb97e47206a9b1c0ce064f85dc1403314ba38f04eaa` |
| `accidents.txt` | 340.183 | 468 | 33,81 | 340.183 / 468 / 33,8 ✅ | [SPMF](https://www.philippe-fournier-viger.com/spmf/publicdatasets/accidents.txt) | `8c2275550966e3cb4b6066f2bb168489a9566c500af559fa3925f1b11d97f0cd` |
| `T10I4D100K.txt` | 100.000 | 870 | 10,10 | 100.000 / 870 / 10,1 ✅ | [SPMF](https://www.philippe-fournier-viger.com/spmf/publicdatasets/T10I4D100K.txt) | `949983f61aa976d1b774474fadd31c5f15775b24728a5e7c8b79801822ab3f89` |

## Ghi chú

- **Mushroom có hai phiên bản.** Bản trên trang SPMF (`mushrooms.txt`) có **8.416** giao dịch, khác bảng của đề. Nhóm dùng bản gốc của FIMI (**8.124** giao dịch, khớp đề). File FIMI gốc có dấu cách ở cuối mỗi dòng; script tải về sẽ bỏ dấu cách đó (SHA-256 của file gốc: `6cf94bc482712c3936f0b40c921381ab2b776c3d9941880fecac4d83ca5cbeb5`).
- Bảng của đề ghi số item của Retail là "16.47"; số đúng là 16.470.
- Mã item của T10I4D100K nằm trong khoảng 1..1000 nhưng chỉ có 870 mã thực sự xuất hiện, nên bộ đọc phải đổi mã về 1..m (xem `read_spmf`).
- Mọi file đều đã kiểm tra: item là số nguyên dương, mỗi giao dịch đã sắp xếp và không có item trùng, các item cách nhau đúng một dấu cách. SPMF báo lỗi nếu có dấu tab, hai dấu cách liền nhau, dấu cách ở đầu dòng, hoặc item trùng trong một giao dịch (xem `results/spmf_behavior.md`).

## Dữ liệu cho Chương 3

| File | Dùng cho | Nguồn | SHA-256 |
|---|---|---|---|
| `data/apps/groceries/groceries.csv` (9.835 giao dịch) | Ứng dụng 1 | [Machine-Learning-with-R-datasets](https://raw.githubusercontent.com/stedy/Machine-Learning-with-R-datasets/master/groceries.csv) (bản Groceries của gói `arules`) | `ff1be892fd6b9b57d1a7bc50de067798963dda607619645988b21789bf23ae3b` |
| `data/apps/caltech101/caltech-101.zip` | Ứng dụng 2 | [CaltechDATA](https://data.caltech.edu/records/mzrjq-6wc02), giấy phép CC BY 4.0 | `331234750fc7f77520e50d9565e8b6907b03565e30320da1401130db08c61f91` |
