# Các phép toán trên tidset (phần của A).
#
# Nhắc lại: tidset của một tập X là danh sách mã các giao dịch (tid) có chứa X, và
# support(X) = số phần tử của tidset. Eclat tính tidset của tập lớn bằng cách GIAO tidset của
# hai tập con: t(X ∪ Y) = t(X) ∩ t(Y) (bài báo Zaki 2000, §4.1). Gần như toàn bộ thời gian chạy
# nằm ở phép giao, nên các hàm trong file này là "vòng lặp nóng" của cả chương trình.
#
# Tidset dạng vector: danh sách mã giao dịch (tid) TĂNG DẦN, kiểu Int32.
# Tidset luôn tăng dần vì được dựng bằng cách duyệt giao dịch theo tid tăng dần.
# Dùng Int32 thay vì Int64 vì tốn một nửa bộ nhớ mà vẫn đủ cho tới khoảng 2 tỉ giao dịch.
#
# Hai nhóm hàm:
#   - intersect_merge(a, b): bản cơ bản (v0), cấp phát mảng kết quả mới;
#   - isect_*!(dst, dpos, a, ao, la, b, bo, lb, ...): ghi kết quả vào vùng nhớ có sẵn
#     dst[dpos : dpos+c-1], không cấp phát (dùng cho v2 trở đi). Tidset nguồn là đoạn
#     a[ao : ao+la-1] và b[bo : bo+lb-1] của các buffer dùng lại.
#
# Quy ước tên tham số dùng chung trong file:
#   dst, dpos : mảng đích và vị trí bắt đầu ghi kết quả;
#   a, ao, la : buffer chứa tidset thứ nhất, vị trí bắt đầu (offset) và độ dài của nó;
#   b, bo, lb : tương tự cho tidset thứ hai;
#   c         : số phần tử chung tìm được = support của tập mới.
# Hàm có dấu "!" ở cuối tên là hàm GHI VÀO tham số (quy ước của Julia), ở đây là ghi vào dst.

"""
    intersect_merge(a, b) -> Vector{Int32}

Giao hai tidset đã sắp xếp bằng **trộn hai con trỏ** (bản cơ bản, v0).
Cấp phát một mảng kết quả mới cho mỗi lần gọi.

Mỗi bước, ít nhất một con trỏ tiến lên, nên độ phức tạp là O(|a| + |b|).
"""
function intersect_merge(a::Vector{Int32}, b::Vector{Int32})
    out = Vector{Int32}(undef, min(length(a), length(b)))   # kết quả không dài hơn mảng ngắn hơn
    # Dùng lại đúng thuật toán của isect_merge! bên dưới để hai bản luôn cho cùng kết quả;
    # ghi từ ô 1 của out, đọc toàn bộ a (từ ô 1, dài length(a)) và toàn bộ b.
    c = isect_merge!(out, 1, a, 1, length(a), b, 1, length(b))
    return resize!(out, c)                                  # cắt bỏ phần ô thừa, chỉ giữ c phần tử chung
end

# @inline (dùng cho nhiều hàm trong file): gợi ý trình biên dịch chép thân hàm vào chỗ gọi,
# bỏ chi phí gọi hàm trong vòng lặp nóng.
"""
    isect_merge!(dst, dpos, a, ao, la, b, bo, lb) -> c

Trộn hai con trỏ, ghi phần giao vào `dst[dpos:dpos+c-1]`, trả về số phần tử chung `c`.
Không cấp phát. O(la + lb).
"""
@inline function isect_merge!(dst::Vector{Int32}, dpos::Int, a::Vector{Int32}, ao::Int, la::Int,
                              b::Vector{Int32}, bo::Int, lb::Int)
    i = ao                  # con trỏ đọc trong tidset a, bắt đầu ở đầu đoạn của a
    iend = ao + la - 1      # vị trí cuối cùng của đoạn a trong buffer
    j = bo                  # con trỏ đọc trong tidset b
    jend = bo + lb - 1      # vị trí cuối cùng của đoạn b
    c = 0                   # số phần tử chung đã tìm được, cũng là số ô đã ghi vào dst
    # @inbounds: bỏ kiểm tra chỉ số mảng để chạy nhanh hơn. An toàn vì điều kiện của while đã bảo đảm
    # i ≤ iend và j ≤ jend; khi chạy test với --check-bounds=yes, Julia vẫn kiểm tra lại (CI làm việc này).
    @inbounds while i <= iend && j <= jend      # dừng khi một trong hai danh sách đã duyệt hết
        x = a[i]
        y = b[j]
        if x == y               # tid có mặt ở cả hai danh sách → thuộc phần giao
            dst[dpos+c] = x     # ghi vào ô trống kế tiếp của dst
            c += 1
            i += 1              # cả hai con trỏ cùng tiến
            j += 1
        elseif x < y            # b tăng dần nên mọi phần tử còn lại của b đều ≥ y > x: x không thể chung
            i += 1
        else                    # ngược lại y < x: y không thể chung
            j += 1
        end
    end
    return c
end

"""
Tỉ lệ độ dài để chuyển từ trộn sang tìm kiếm nhảy (galloping): khi mảng dài gấp ≥ 16 lần
mảng ngắn, nhảy trong mảng dài rẻ hơn duyệt hết nó.
"""
const GALLOP_RATIO = 16     # const: hằng số toàn cục, trình biên dịch biết kiểu nên không làm chậm code

"""
Tìm vị trí đầu tiên `p ∈ [j, jend]` có `b[p] ≥ x` bằng tìm kiếm nhảy (Bentley & Yao, 1976):
nhảy 1, 2, 4, 8… bước cho tới khi vượt `x`, rồi tìm nhị phân trong đoạn cuối.
Trả về `jend + 1` nếu không có. O(log(p - j)).
"""
@inline function _gallop(b::Vector{Int32}, j::Int, jend::Int, x::Int32)
    @inbounds b[j] >= x && return j     # trường hợp hay gặp nhất: ngay vị trí hiện tại đã ≥ x
    # Giai đoạn 1 (nhảy): tìm một đoạn [lo, hi] chắc chắn chứa đáp án, với độ dài bước tăng gấp đôi.
    lo = j                 # bất biến: b[lo] < x
    step = 1
    hi = j + 1
    @inbounds while hi <= jend && b[hi] < x     # b[hi] vẫn < x thì đáp án còn ở xa hơn
        lo = hi            # dời mốc trái lên (vẫn giữ b[lo] < x)
        step <<= 1         # gấp đôi bước nhảy (<<= 1 là nhân 2 bằng phép dịch bit)
        hi = lo + step
    end
    hi = min(hi, jend + 1) # không để hi vượt quá cuối đoạn; jend + 1 nghĩa là "không tìm thấy"
    # Giai đoạn 2 (tìm nhị phân) trong (lo, hi]: đoạn này dài tối đa bằng bước nhảy cuối cùng.
    @inbounds while hi - lo > 1          # b[lo] < x ≤ b[hi] (hoặc hi = jend + 1)
        mid = (lo + hi) >>> 1            # điểm giữa; >>> 1 là chia 2 bằng dịch bit
        if b[mid] < x
            lo = mid                     # đáp án nằm bên phải mid
        else
            hi = mid                     # mid đã ≥ x: đáp án là mid hoặc nằm bên trái
        end
    end
    return hi
end

"""
    isect_adaptive!(dst, dpos, a, ao, la, b, bo, lb, minsup) -> c

Phép giao **thích ứng** (v3), ghi vào `dst` như `isect_merge!`, với hai cải tiến:

1. **Ngắt sớm:** nếu số phần tử chung đã có cộng số phần tử còn lại tối đa vẫn `< minsup`
   thì dừng ngay, vì kết quả chắc chắn không phổ biến. Khi đó giá trị trả về `< minsup`.
2. **Tìm kiếm nhảy:** khi một mảng dài gấp ≥ `GALLOP_RATIO` lần mảng kia, duyệt mảng ngắn và
   nhảy trong mảng dài: O(la · log(lb/la)) thay vì O(la + lb). Hay gặp trên dữ liệu thưa,
   khi item hiếm giao với item phổ biến.

Kết quả (khi `c ≥ minsup`) giống hệt `isect_merge!`.
"""
@inline function isect_adaptive!(dst::Vector{Int32}, dpos::Int, a::Vector{Int32}, ao::Int, la::Int,
                                 b::Vector{Int32}, bo::Int, lb::Int, minsup::Int)
    if la > lb                                   # để a luôn là mảng ngắn hơn
        a, b = b, a                              # đổi chỗ cả buffer, offset và độ dài cho khớp
        ao, bo = bo, ao
        la, lb = lb, la
    end
    # Phần giao không dài hơn mảng ngắn, nên mảng ngắn đã < minsup thì kết quả chắc chắn trượt ngưỡng.
    la < minsup && return 0                      # không thể đủ ngưỡng
    c = 0                                        # số phần tử chung đã tìm được
    jend = bo + lb - 1                           # vị trí cuối của đoạn b (mảng dài)
    # --- Nhánh 1: b dài gấp ≥ 16 lần a → với mỗi phần tử của a, "nhảy" trong b để tìm nó ---
    if lb >= GALLOP_RATIO * la
        j = bo                                   # vị trí đang đứng trong b; chỉ tiến, không lùi
        @inbounds for i in 0:(la-1)              # i = số phần tử của a đã xét
            # Còn (la - i) phần tử của a chưa xét, mỗi phần tử góp nhiều nhất 1 vào c.
            c + (la - i) < minsup && return c    # ngắt sớm
            x = a[ao+i]                          # phần tử thứ i của a
            j = _gallop(b, j, jend, x)           # vị trí đầu tiên trong b có giá trị ≥ x
            j > jend && return c                 # b đã hết: không còn phần tử chung nào nữa
            if b[j] == x                         # tìm thấy x trong b → x thuộc phần giao
                dst[dpos+c] = x
                c += 1
                j += 1                           # phần tử tiếp theo của a lớn hơn x, nên bỏ qua b[j]
                j > jend && return c
            end
        end
        return c
    end
    # --- Nhánh 2: hai mảng dài gần bằng nhau → trộn hai con trỏ như isect_merge!, thêm ngắt sớm ---
    i = ao
    iend = ao + la - 1
    j = bo
    @inbounds while i <= iend && j <= jend
        # Số phần tử chung còn có thể tìm thêm ≤ số phần tử còn lại của mảng ít hơn
        # = min(iend - i + 1, jend - j + 1) = min(iend - i, jend - j) + 1.
        c + min(iend - i, jend - j) + 1 < minsup && return c   # ngắt sớm
        x = a[i]
        y = b[j]
        if x == y                                # giống isect_merge!
            dst[dpos+c] = x
            c += 1
            i += 1
            j += 1
        elseif x < y
            i += 1
        else
            j += 1
        end
    end
    return c
end
