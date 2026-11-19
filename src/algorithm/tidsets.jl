# Các phép toán trên tidset (phần của A).
#
# Tidset dạng vector: danh sách mã giao dịch (tid) TĂNG DẦN, kiểu Vector{Int32}.
# Tidset luôn tăng dần vì được dựng bằng cách duyệt giao dịch theo tid tăng dần (to_vertical).

"""
    intersect_merge(a, b) -> Vector{Int32}

Giao hai tidset đã sắp xếp bằng **trộn hai con trỏ** (bản cơ bản, v0).
Cấp phát một mảng kết quả mới cho mỗi lần gọi.

Mỗi bước, ít nhất một con trỏ tiến lên, nên độ phức tạp là O(|a| + |b|).
"""
function intersect_merge(a::Vector{Int32}, b::Vector{Int32})
    out = Vector{Int32}(undef, min(length(a), length(b)))   # kết quả không dài hơn mảng ngắn hơn
    i = 1
    j = 1
    k = 0
    la = length(a)
    lb = length(b)
    @inbounds while i <= la && j <= lb
        x = a[i]
        y = b[j]
        if x == y
            k += 1
            out[k] = x
            i += 1
            j += 1
        elseif x < y
            i += 1
        else
            j += 1
        end
    end
    return resize!(out, k)
end
