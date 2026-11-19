# Các phép toán trên tidset (phần của A).
#
# Tidset dạng vector: danh sách mã giao dịch (tid) TĂNG DẦN, kiểu Int32.
# Tidset luôn tăng dần vì được dựng bằng cách duyệt giao dịch theo tid tăng dần.
#
# Ba nhóm hàm:
#   - intersect_merge(a, b): bản cơ bản (v0), cấp phát mảng kết quả mới;
#   - isect_*!(dst, dpos, a, ao, la, b, bo, lb, ...): ghi kết quả vào vùng nhớ có sẵn
#     dst[dpos : dpos+c-1], không cấp phát (dùng cho v2 trở đi). Tidset nguồn là đoạn
#     a[ao : ao+la-1] và b[bo : bo+lb-1] của các buffer dùng lại;
#   - and_count!, and_extract!: tidset dạng mảng bit (BitVector, v4 trở đi), bit thứ tid = 1
#     nếu giao dịch tid chứa tập. Mỗi phép toán xử lý 64 giao dịch một lúc.

"""
    intersect_merge(a, b) -> Vector{Int32}

Giao hai tidset đã sắp xếp bằng **trộn hai con trỏ** (bản cơ bản, v0).
Cấp phát một mảng kết quả mới cho mỗi lần gọi.

Mỗi bước, ít nhất một con trỏ tiến lên, nên độ phức tạp là O(|a| + |b|).
"""
function intersect_merge(a::Vector{Int32}, b::Vector{Int32})
    out = Vector{Int32}(undef, min(length(a), length(b)))   # kết quả không dài hơn mảng ngắn hơn
    c = isect_merge!(out, 1, a, 1, length(a), b, 1, length(b))
    return resize!(out, c)
end

"""
    isect_merge!(dst, dpos, a, ao, la, b, bo, lb) -> c

Trộn hai con trỏ, ghi phần giao vào `dst[dpos:dpos+c-1]`, trả về số phần tử chung `c`.
Không cấp phát. O(la + lb).
"""
@inline function isect_merge!(dst::Vector{Int32}, dpos::Int, a::Vector{Int32}, ao::Int, la::Int,
                              b::Vector{Int32}, bo::Int, lb::Int)
    i = ao
    iend = ao + la - 1
    j = bo
    jend = bo + lb - 1
    c = 0
    @inbounds while i <= iend && j <= jend
        x = a[i]
        y = b[j]
        if x == y
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

"""
Tỉ lệ độ dài để chuyển từ trộn sang tìm kiếm nhảy (galloping): khi mảng dài gấp ≥ 16 lần
mảng ngắn, nhảy trong mảng dài rẻ hơn duyệt hết nó.
"""
const GALLOP_RATIO = 16

"""
Tìm vị trí đầu tiên `p ∈ [j, jend]` có `b[p] ≥ x` bằng tìm kiếm nhảy (Bentley & Yao, 1976):
nhảy 1, 2, 4, 8… bước cho tới khi vượt `x`, rồi tìm nhị phân trong đoạn cuối.
Trả về `jend + 1` nếu không có. O(log(p - j)).
"""
@inline function _gallop(b::Vector{Int32}, j::Int, jend::Int, x::Int32)
    @inbounds b[j] >= x && return j
    lo = j                 # bất biến: b[lo] < x
    step = 1
    hi = j + 1
    @inbounds while hi <= jend && b[hi] < x
        lo = hi
        step <<= 1
        hi = lo + step
    end
    hi = min(hi, jend + 1)
    @inbounds while hi - lo > 1          # b[lo] < x ≤ b[hi] (hoặc hi = jend + 1)
        mid = (lo + hi) >>> 1
        if b[mid] < x
            lo = mid
        else
            hi = mid
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
        a, b = b, a
        ao, bo = bo, ao
        la, lb = lb, la
    end
    la < minsup && return 0                      # không thể đủ ngưỡng
    c = 0
    jend = bo + lb - 1
    if lb >= GALLOP_RATIO * la
        j = bo
        @inbounds for i in 0:(la-1)
            c + (la - i) < minsup && return c    # ngắt sớm
            x = a[ao+i]
            j = _gallop(b, j, jend, x)
            j > jend && return c
            if b[j] == x
                dst[dpos+c] = x
                c += 1
                j += 1
                j > jend && return c
            end
        end
        return c
    end
    i = ao
    iend = ao + la - 1
    j = bo
    @inbounds while i <= iend && j <= jend
        c + min(iend - i, jend - j) + 1 < minsup && return c   # ngắt sớm
        x = a[i]
        y = b[j]
        if x == y
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

# ---------------------------------------------------------------------------
# Tidset dạng mảng bit (BitVector)
# ---------------------------------------------------------------------------
# BitVector lưu bit trong trường `chunks::Vector{UInt64}` (64 giao dịch mỗi word) và luôn giữ các
# bit thừa của word cuối bằng 0. Phép AND giữ nguyên tính chất đó, nên có thể làm việc thẳng trên
# từng word: nhanh hơn nhiều so với duyệt từng bit.

"""
    and_count!(dst, a, b) -> c

`dst = a .& b` theo từng word 64-bit, trả về số bit 1 (= support của tập mới).
Không cấp phát; vòng lặp được vector hóa (`@simd`). O(N / 64), không phụ thuộc support.
"""
@inline function and_count!(dst::BitVector, a::BitVector, b::BitVector)
    dc = dst.chunks
    ac = a.chunks
    bc = b.chunks
    c = 0
    @inbounds @simd for w in eachindex(dc)
        v = ac[w] & bc[w]
        dc[w] = v
        c += count_ones(v)
    end
    return c
end

"""
    and_extract!(dst, dpos, a, b) -> c

Tính `a .& b` và ghi **danh sách tid** (vị trí các bit 1, tăng dần) vào `dst[dpos:dpos+c-1]`.
Dùng khi bản lai (v6) chuyển một lớp từ dạng bitset sang dạng vector. O(N / 64 + c).
"""
@inline function and_extract!(dst::Vector{Int32}, dpos::Int, a::BitVector, b::BitVector)
    ac = a.chunks
    bc = b.chunks
    c = 0
    @inbounds for w in eachindex(ac)
        v = ac[w] & bc[w]
        base = (w - 1) << 6
        while v != 0
            dst[dpos+c] = Int32(base + trailing_zeros(v) + 1)
            c += 1
            v &= v - 1                     # xóa bit 1 thấp nhất
        end
    end
    return c
end
