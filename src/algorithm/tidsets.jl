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
# Ba nhóm hàm:
#   - intersect_merge(a, b): bản cơ bản (v0), cấp phát mảng kết quả mới;
#   - isect_*!(dst, dpos, a, ao, la, b, bo, lb, ...): ghi kết quả vào vùng nhớ có sẵn
#     dst[dpos : dpos+c-1], không cấp phát (dùng cho v2 trở đi). Tidset nguồn là đoạn
#     a[ao : ao+la-1] và b[bo : bo+lb-1] của các buffer dùng lại;
#   - and_count!, and_extract!: tidset dạng mảng bit (BitVector, v4 trở đi), bit thứ tid = 1
#     nếu giao dịch tid chứa tập. Mỗi phép toán xử lý 64 giao dịch một lúc.
#
# Quy ước tên tham số dùng chung trong file:
#   dst, dpos : mảng đích và vị trí bắt đầu ghi kết quả;
#   a, ao, la : buffer chứa tidset thứ nhất, vị trí bắt đầu (offset) và độ dài của nó;
#   b, bo, lb : tương tự cho tidset thứ hai;
#   c         : số phần tử chung tìm được = support của tập mới.
# Hàm có dấu "!" ở cuối tên là hàm GHI VÀO tham số (quy ước của Julia), ở đây là ghi vào dst.
#
# [VẤN ĐÁP] CẢ FILE
# HỎI–ĐÁP   : H: Vì sao không dùng Set{Int} và hàm intersect có sẵn của Julia?
#             Đ: Set phải băm từng phần tử và cấp phát bảng băm mới cho mỗi kết quả, không dừng sớm được; mảng đã sắp
#                xếp cho phép giao hai con trỏ O(|a|+|b|), bộ nhớ liền nhau (thân thiện bộ nhớ đệm CPU) và không cấp phát.
#                Test xác nhận: kết quả giống intersect của Julia trên 2.000 ca ngẫu nhiên, và @allocated = 0.
#             H: Vì sao tham số rườm rà (buffer, offset, độ dài) thay vì truyền hai mảng?
#             Đ: Từ v2, mọi tidset của một lớp nằm liền nhau trong MỘT buffer; truyền (buffer, offset, độ dài) để
#                đọc một đoạn mà không phải sao chép hay cấp phát mảng con.

# [VẤN ĐÁP] intersect_merge (v0, v1)
# LÀM GÌ    : giao hai tidset, trả về mảng MỚI chứa phần chung.
# VÌ SAO    : là cách viết thẳng theo bài báo, dùng cho bản cơ bản; v2 trở đi thay bằng isect_*! không cấp phát.
# BẰNG CHỨNG: test_performance.jl: bản cấp phát (v0) xin 9,91 MiB, bản dùng lại vùng nhớ (v2) chỉ 0,27 MiB (≈ 37 lần ít hơn).
"""
    intersect_merge(a, b) -> Vector{Int32}

Giao hai tidset đã sắp xếp bằng **trộn hai con trỏ** (bản cơ bản, v0).
Cấp phát một mảng kết quả mới cho mỗi lần gọi.

Mỗi bước, ít nhất một con trỏ tiến lên, nên độ phức tạp là O(|a| + |b|).
"""
function intersect_merge(a::Vector{Int32}, b::Vector{Int32})   # v0, v1
    out = Vector{Int32}(undef, min(length(a), length(b)))   # kết quả không dài hơn mảng ngắn hơn
    # Dùng lại đúng thuật toán của isect_merge! bên dưới để hai bản luôn cho cùng kết quả;
    # ghi từ ô 1 của out, đọc toàn bộ a (từ ô 1, dài length(a)) và toàn bộ b.
    c = isect_merge!(out, 1, a, 1, length(a), b, 1, length(b))
    return resize!(out, c)                                  # cắt bỏ phần ô thừa, chỉ giữ c phần tử chung
end

# @inline (dùng cho nhiều hàm trong file): gợi ý trình biên dịch chép thân hàm vào chỗ gọi,
# bỏ chi phí gọi hàm trong vòng lặp nóng.
#
# [VẤN ĐÁP] isect_merge! (v2) — giao hai con trỏ
# LÀM GÌ    : so a[i] với b[j]: bằng → ghi, cả hai tiến; nhỏ hơn → bỏ phần tử nhỏ (nó không thể có ở mảng kia).
# VÌ SAO    : "x < y thì bỏ x" đúng vì b tăng dần: mọi phần tử còn lại của b ≥ y > x. Đây là lý do tidset phải tăng dần.
# CHI PHÍ   : mỗi bước ít nhất một con trỏ tiến, không con trỏ nào lùi → tối đa la + lb bước, O(la + lb); không cấp phát.
# HỎI–ĐÁP   : H: @inbounds có nguy hiểm không? Đ: Nó bỏ kiểm tra chỉ số; an toàn vì điều kiện while bảo đảm i ≤ iend,
#                j ≤ jend, và CI chạy toàn bộ test lại với --check-bounds=yes (bật lại kiểm tra) đều qua.
"""
    isect_merge!(dst, dpos, a, ao, la, b, bo, lb) -> c

Trộn hai con trỏ, ghi phần giao vào `dst[dpos:dpos+c-1]`, trả về số phần tử chung `c`.
Không cấp phát. O(la + lb).
"""
@inline function isect_merge!(dst::Vector{Int32}, dpos::Int, a::Vector{Int32}, ao::Int, la::Int,   # v2
                              b::Vector{Int32}, bo::Int, lb::Int)   # (tiếp tham số)
    i = ao                  # con trỏ đọc trong tidset a, bắt đầu ở đầu đoạn của a
    iend = ao + la - 1      # vị trí cuối cùng của đoạn a trong buffer
    j = bo                  # con trỏ đọc trong tidset b
    jend = bo + lb - 1      # vị trí cuối cùng của đoạn b
    c = 0                   # số phần tử chung đã tìm được, cũng là số ô đã ghi vào dst
    # @inbounds: bỏ kiểm tra chỉ số mảng để chạy nhanh hơn. An toàn vì điều kiện của while đã bảo đảm
    # i ≤ iend và j ≤ jend; khi chạy test với --check-bounds=yes, Julia vẫn kiểm tra lại (CI làm việc này).
    @inbounds while i <= iend && j <= jend      # dừng khi một trong hai danh sách đã duyệt hết
        x = a[i]            # phần tử hiện tại của a
        y = b[j]            # phần tử hiện tại của b
        if x == y               # tid có mặt ở cả hai danh sách → thuộc phần giao
            dst[dpos+c] = x     # ghi vào ô trống kế tiếp của dst
            c += 1              # thêm một phần tử chung
            i += 1              # cả hai con trỏ cùng tiến
            j += 1   # con trỏ b tiến
        elseif x < y            # b tăng dần nên mọi phần tử còn lại của b đều ≥ y > x: x không thể chung
            i += 1   # con trỏ a tiến
        else                    # ngược lại y < x: y không thể chung
            j += 1   # con trỏ b tiến
        end
    end
    return c                # c = support của tập mới
end

# [VẤN ĐÁP] GALLOP_RATIO
# VÌ SAO    : tìm kiếm galloping tốn khoảng 2·log2(khoảng cách) phép so sánh cho mỗi phần tử của a; trộn tốn khoảng
#             lb/la + 1 bước cho mỗi phần tử của a. Ở tỉ lệ 16: galloping ≈ 8 so sánh, trộn ≈ 17 bước → galloping rẻ hơn.
# HỎI–ĐÁP   : H: 16 từ đâu ra, có tinh chỉnh bằng thực nghiệm không?
#             Đ: Chọn theo ước lượng trên (ngưỡng an toàn, galloping chắc chắn có lợi), KHÔNG tinh chỉnh bằng thực nghiệm;
#                tinh chỉnh hằng số này theo máy là một hướng cải tiến.
"""
Tỉ lệ độ dài để chuyển từ trộn sang tìm kiếm nhảy (galloping): khi mảng dài gấp ≥ 16 lần
mảng ngắn, nhảy trong mảng dài rẻ hơn duyệt hết nó.
"""
const GALLOP_RATIO = 16     # const: hằng số toàn cục, trình biên dịch biết kiểu nên không làm chậm code

# [VẤN ĐÁP] _gallop — tìm kiếm galloping (exponential search, Bentley & Yao 1976)
# LÀM GÌ    : tìm vị trí đầu tiên p ≥ j có b[p] ≥ x: nhảy 1, 2, 4, 8... bước cho tới khi vượt x, rồi tìm nhị phân.
# CHI PHÍ   : O(log(p - j)): khoảng cách d tốn ≈ log2(d) bước nhảy + log2(d) bước nhị phân.
# HỎI–ĐÁP   : H: Sao không tìm nhị phân trên cả mảng b? Đ: nhị phân toàn mảng tốn log2(lb) mỗi lần, kể cả khi phần tử
#                cần tìm ở ngay gần; galloping chỉ tốn theo khoảng cách thật, và con trỏ j chỉ tiến (không tìm lại từ đầu).
"""
Tìm vị trí đầu tiên `p ∈ [j, jend]` có `b[p] ≥ x` bằng tìm kiếm nhảy (Bentley & Yao, 1976):
nhảy 1, 2, 4, 8… bước cho tới khi vượt `x`, rồi tìm nhị phân trong đoạn cuối.
Trả về `jend + 1` nếu không có. O(log(p - j)).
"""
@inline function _gallop(b::Vector{Int32}, j::Int, jend::Int, x::Int32)   # tìm kiếm galloping
    @inbounds b[j] >= x && return j     # trường hợp hay gặp nhất: ngay vị trí hiện tại đã ≥ x
    # Giai đoạn 1 (nhảy): tìm một đoạn [lo, hi] chắc chắn chứa đáp án, với độ dài bước tăng gấp đôi.
    lo = j                 # bất biến: b[lo] < x
    step = 1               # độ dài bước nhảy hiện tại
    hi = j + 1             # vị trí thử tiếp theo
    @inbounds while hi <= jend && b[hi] < x     # b[hi] vẫn < x thì đáp án còn ở xa hơn
        lo = hi            # dời mốc trái lên (vẫn giữ b[lo] < x)
        step <<= 1         # gấp đôi bước nhảy (<<= 1 là nhân 2 bằng phép dịch bit)
        hi = lo + step     # thử vị trí xa hơn gấp đôi
    end
    hi = min(hi, jend + 1) # không để hi vượt quá cuối đoạn; jend + 1 nghĩa là "không tìm thấy"
    # Giai đoạn 2 (tìm nhị phân) trong (lo, hi]: đoạn này dài tối đa bằng bước nhảy cuối cùng.
    @inbounds while hi - lo > 1          # b[lo] < x ≤ b[hi] (hoặc hi = jend + 1)
        mid = (lo + hi) >>> 1            # điểm giữa; >>> 1 là chia 2 bằng dịch bit
        if b[mid] < x   # so với điểm giữa
            lo = mid                     # đáp án nằm bên phải mid
        else
            hi = mid                     # mid đã ≥ x: đáp án là mid hoặc nằm bên trái
        end
    end
    return hi              # vị trí đầu tiên có b[hi] ≥ x (hoặc jend + 1)
end

# [VẤN ĐÁP] isect_adaptive! (v3) — giao thích ứng
# LÀM GÌ    : (1) mảng ngắn < minsup thì trả 0 ngay; (2) dừng sớm khi c + số phần tử còn lại tối đa < minsup;
#             (3) mảng dài gấp ≥ 16 lần mảng ngắn thì dùng galloping thay cho trộn.
# VÌ SAO    : ta chỉ cần biết tập mới CÓ đủ minsup không; khi chắc chắn không đủ thì kết quả cụ thể là vô ích.
# CHI PHÍ   : nhánh galloping O(la·log(lb/la)); nhánh trộn O(la + lb) nhưng thường dừng sớm hơn nhiều.
# BẰNG CHỨNG: E8 minsup thấp nhất (B03, B04): retail 0,1% (99,8% phép giao trượt ngưỡng) v2 → v3 nhanh hơn 2,6 lần;
#             T10I4D100K (95,7% trượt) nhanh hơn 1,4 lần. Nhưng chess (2,5% trượt, hai danh sách dài gần bằng nhau)
#             CHẬM hơn 1,7 lần, mushroom chậm hơn 1,4 lần: phép kiểm tra thêm mỗi vòng lặp không bao giờ có lợi ở đó.
# HỎI–ĐÁP   : H: Kết quả khi dừng sớm có sai không? Đ: Khi c ≥ minsup kết quả giống hệt isect_merge!; khi dừng sớm
#                giá trị trả về < minsup nên tập bị loại đúng như trước. Test kiểm tra cả ba mức ngưỡng trên 2.000 ca.
#             H: Vì sao v3 chậm hơn v2 trên chess mà vẫn giữ? Đ: v3 là bước của ablation; bản mặc định v6 dùng dãy bit
#                trên dữ liệu dày nên không đi qua hàm này ở đó.
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
@inline function isect_adaptive!(dst::Vector{Int32}, dpos::Int, a::Vector{Int32}, ao::Int, la::Int,   # v3
                                 b::Vector{Int32}, bo::Int, lb::Int, minsup::Int)   # (tiếp tham số; minsup để dừng sớm)
    if la > lb                                   # để a luôn là mảng ngắn hơn
        a, b = b, a                              # đổi chỗ cả buffer, offset và độ dài cho khớp
        ao, bo = bo, ao   # đổi offset
        la, lb = lb, la   # đổi độ dài
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
                dst[dpos+c] = x                  # ghi phần tử chung
                c += 1   # thêm một phần tử chung
                j += 1                           # phần tử tiếp theo của a lớn hơn x, nên bỏ qua b[j]
                j > jend && return c             # b đã hết
            end
        end
        return c                                 # đã xét hết a
    end
    # --- Nhánh 2: hai mảng dài gần bằng nhau → trộn hai con trỏ như isect_merge!, thêm ngắt sớm ---
    i = ao                                       # con trỏ trong a
    iend = ao + la - 1                           # cuối đoạn a
    j = bo                                       # con trỏ trong b
    @inbounds while i <= iend && j <= jend   # trộn như isect_merge!
        # Số phần tử chung còn có thể tìm thêm ≤ số phần tử còn lại của mảng ít hơn
        # = min(iend - i + 1, jend - j + 1) = min(iend - i, jend - j) + 1.
        c + min(iend - i, jend - j) + 1 < minsup && return c   # ngắt sớm
        x = a[i]   # phần tử của a
        y = b[j]   # phần tử của b
        if x == y                                # giống isect_merge!
            dst[dpos+c] = x   # ghi phần tử chung
            c += 1   # thêm một phần tử chung
            i += 1   # con trỏ a tiến
            j += 1   # con trỏ b tiến
        elseif x < y                             # x không thể có trong b
            i += 1   # con trỏ a tiến
        else                                     # y không thể có trong a
            j += 1   # con trỏ b tiến
        end
    end
    return c   # số phần tử chung (support)
end

# ---------------------------------------------------------------------------
# Tidset dạng mảng bit (BitVector)
# ---------------------------------------------------------------------------
# BitVector lưu bit trong trường `chunks::Vector{UInt64}` (64 giao dịch mỗi word) và luôn giữ các
# bit thừa của word cuối bằng 0. Phép AND giữ nguyên tính chất đó, nên có thể làm việc thẳng trên
# từng word: nhanh hơn nhiều so với duyệt từng bit.
#
# Ví dụ: tid 1..64 nằm trong word 1, tid 65..128 nằm trong word 2, ...; tid t ứng với bit thứ
# (t - 1) mod 64 của word thứ ⌊(t - 1) / 64⌋ + 1.
# Vì sao nhanh trên dữ liệu dày: một phép AND trên 2 word xử lý 64 giao dịch cùng lúc, và
# count_ones đếm số bit 1 bằng một lệnh máy (popcnt). Bù lại, chi phí luôn là N/64 word,
# kể cả khi tidset rất ngắn; vì vậy dữ liệu thưa thì dạng vector vẫn lợi hơn (lý do có bản lai v6).

# [VẤN ĐÁP] and_count! (v4)
# LÀM GÌ    : dst = a AND b theo từng word 64 bit; support = tổng số bit 1.
# CHI PHÍ   : N/64 phép AND + popcnt, KHÔNG phụ thuộc support; không có lệnh rẽ nhánh nên CPU chạy đều, @simd xử lý
#             nhiều word trong một lệnh. Bộ nhớ một tidset N/8 byte (danh sách: 4σ byte).
# BẰNG CHỨNG: E8 minsup thấp nhất: chess v3 → v4 nhanh hơn 17,7 lần, mushroom 11,6 lần, tidset đỉnh nhỏ hơn 9–27 lần.
#             Retail 0,1%: chậm hơn 1,7 lần và tốn bộ nhớ gấp 8,4 lần (22,45 so với 2,66 MiB) → đúng dự đoán dữ liệu thưa.
#             E7: về thời gian dãy bit đã thắng từ mật độ ρ ≈ 0,004 (thấp hơn ngưỡng bộ nhớ 1/32 gần 10 lần).
# HỎI–ĐÁP   : H: Vì sao đọc thẳng trường .chunks (nội bộ của BitVector)? Đ: a .& b của Julia cấp phát BitVector mới và
#                count_ones phải duyệt lại lần nữa; làm thẳng trên word gộp AND, ghi và đếm trong một vòng, không cấp phát.
#                BitVector luôn giữ các bit thừa của word cuối bằng 0, và AND giữ nguyên điều đó, nên đếm vẫn đúng.
"""
    and_count!(dst, a, b) -> c

`dst = a .& b` theo từng word 64-bit, trả về số bit 1 (= support của tập mới).
Không cấp phát; vòng lặp được vector hóa (`@simd`). O(N / 64), không phụ thuộc support.
"""
@inline function and_count!(dst::BitVector, a::BitVector, b::BitVector)   # v4
    dc = dst.chunks         # mảng word 64 bit bên trong mỗi BitVector
    ac = a.chunks   # word của a
    bc = b.chunks   # word của b
    c = 0                   # tổng số bit 1 = số giao dịch chứa tập mới
    # @simd: cho phép CPU xử lý nhiều word trong một lệnh (vector hóa), vì các vòng lặp độc lập nhau.
    @inbounds @simd for w in eachindex(dc)
        v = ac[w] & bc[w]   # AND bit: bit = 1 khi giao dịch có mặt ở CẢ HAI tidset
        dc[w] = v           # lưu tidset mới vào dst
        c += count_ones(v)  # đếm số bit 1 trong word này
    end
    return c                # support của tập mới
end

# [VẤN ĐÁP] and_extract! (v6, chuyển dãy bit → danh sách)
# LÀM GÌ    : AND hai dãy bit rồi xuất thẳng VỊ TRÍ các bit 1 thành danh sách tid tăng dần.
# VÌ SAO    : khi bản lai quyết định lớp con đủ thưa, dựng ngay dạng danh sách mà không cần dãy bit trung gian.
# CHI PHÍ   : O(N/64 + c): duyệt mọi word, mỗi bit 1 tốn một trailing_zeros (một lệnh máy) và một phép xóa bit.
# HỎI–ĐÁP   : H: v &= v - 1 làm gì? Đ: xóa bit 1 thấp nhất (v - 1 lật bit 1 thấp nhất và mọi bit 0 phía dưới nó),
#                nên vòng while chạy đúng số lần bằng số bit 1, không duyệt 64 bit.
"""
    and_extract!(dst, dpos, a, b) -> c

Tính `a .& b` và ghi **danh sách tid** (vị trí các bit 1, tăng dần) vào `dst[dpos:dpos+c-1]`.
Dùng khi bản lai (v6) chuyển một lớp từ dạng bitset sang dạng vector. O(N / 64 + c).
"""
@inline function and_extract!(dst::Vector{Int32}, dpos::Int, a::BitVector, b::BitVector)   # v6
    ac = a.chunks                          # các word 64 bit của a
    bc = b.chunks                          # các word 64 bit của b
    c = 0                                  # số tid đã ghi vào dst
    @inbounds for w in eachindex(ac)       # duyệt từng word, theo thứ tự tid tăng dần
        v = ac[w] & bc[w]                  # 64 giao dịch của word w: bit 1 = có trong phần giao
        base = (w - 1) << 6                # (w - 1) * 64: số giao dịch nằm trong các word đứng trước
        while v != 0                       # còn bit 1 nào trong word thì lấy ra từng bit
            # trailing_zeros(v) = vị trí bit 1 thấp nhất (0..63) → tid = base + vị trí + 1.
            dst[dpos+c] = Int32(base + trailing_zeros(v) + 1)
            c += 1                         # thêm một tid
            v &= v - 1                     # xóa bit 1 thấp nhất
        end
    end
    return c                               # support của tập mới
end
