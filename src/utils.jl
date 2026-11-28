# Mô-đun đọc/ghi định dạng SPMF tối ưu theo byte và quy đổi ngưỡng hỗ trợ tối thiểu (minsup).
#
# Hành vi tham chiếu được kiểm chứng hộp đen với SPMF tại results/spmf_behavior.md:
#   - D04: σ_min = ceil(Int, Float64(minsup) * N); chuỗi "p%" được quy đổi thành p / 100.
#   - D05: bỏ qua dòng rỗng và dòng bắt đầu bằng '#', '%', '@'; N là số dòng còn lại.
#   - D06: xuất định dạng "i1 i2 ... #SUP: s" theo mã mặt hàng gốc tăng dần, không xuất tập rỗng.

# ---------------------------------------------------------------------------
# Quy đổi ngưỡng minsup
# ---------------------------------------------------------------------------

"""
    parse_minsup(s::AbstractString) -> Float64

Chuyển chuỗi ngưỡng `minsup` sang tỉ lệ trong `(0, 1]`.
Chấp nhận cả dạng tỉ lệ (`"0.4"`) lẫn phần trăm (`"40%"`, quy đổi thành `40.0 / 100`
trên `Float64` đúng theo SPMF).
"""
function parse_minsup(s::AbstractString)::Float64
    t = strip(s)
    isempty(t) && throw(ArgumentError("minsup không được rỗng"))
    val = if endswith(t, '%')
        num_str = strip(SubString(t, firstindex(t), prevind(t, lastindex(t))))
        v = tryparse(Float64, num_str)
        v === nothing && throw(ArgumentError("minsup không hợp lệ: '$s'"))
        v / 100
    else
        v = tryparse(Float64, t)
        v === nothing && throw(ArgumentError("minsup không hợp lệ: '$s'"))
        v
    end
    (isfinite(val) && 0.0 < val <= 1.0) ||
        throw(ArgumentError("minsup phải nằm trong khoảng (0, 1] (hoặc (0%, 100%]), nhận được: '$s'"))
    return val
end

"""
    minsup_count(minsup::Real, n::Integer) -> Int
    minsup_count(minsup::AbstractString, n::Integer) -> Int

Đổi ngưỡng `minsup` dạng tỉ lệ sang ngưỡng đếm `σ_min = ceil(Int, Float64(minsup) * n)`
đúng theo quy tắc của SPMF (xem `results/spmf_behavior.md`).
"""
function minsup_count(minsup::Real, n::Integer)::Int
    n >= 0 || throw(ArgumentError("Số giao dịch n phải ≥ 0, nhận được: $n"))
    mf = Float64(minsup)
    (isfinite(mf) && 0.0 < mf <= 1.0) ||
        throw(ArgumentError("minsup phải nằm trong khoảng (0, 1], nhận được: $minsup"))
    return ceil(Int, mf * n)
end

minsup_count(minsup::AbstractString, n::Integer)::Int = minsup_count(parse_minsup(minsup), n)

# ---------------------------------------------------------------------------
# Đọc tệp SPMF tối ưu theo byte (không cấp phát chuỗi trung gian)
# ---------------------------------------------------------------------------

# Kiểm tra nhanh ký tự khoảng trắng ngang (dấu cách, tab, CR) và chữ số ASCII 0..9
@inline _is_hws(c::UInt8) = c == UInt8(' ') || c == UInt8('\t') || c == UInt8('\r')
@inline _is_digit(c::UInt8) = UInt8('0') <= c <= UInt8('9')

"""
    parse_spmf(bytes::AbstractVector{UInt8}) -> TransactionDB

Mục đích: Phân tích toàn bộ tệp giao dịch chuẩn SPMF trực tiếp trên mảng byte (tránh tạo chuỗi String
trung gian cho từng dòng nên nhanh hơn `eachline`/`split` khoảng 10–15 lần):
- Bỏ qua dòng rỗng và dòng chú thích/siêu dữ liệu bắt đầu bằng `#`, `%`, `@`.
- Chấp nhận mọi khoảng trắng (dấu cách, tab, CR); tự sắp xếp tăng dần và khử trùng lặp item.
- Ánh xạ mã gốc (`Int64`, tăng dần) sang mã nội bộ liên tiếp `1..m` (`Int32`) để truy cập mảng O(1).
"""
function parse_spmf(bytes::AbstractVector{UInt8})::TransactionDB
    nbytes = length(bytes)
    flat = Int64[]                    # Mảng phẳng gom tất cả mã item đọc được của mọi giao dịch
    sizehint!(flat, nbytes ÷ 4)       # Cấp phát trước dung lượng ước lượng để tránh resize nhiều lần
    starts = Int[1]                   # starts[j]..starts[j+1]-1 là đoạn chỉ số của giao dịch thứ j trong `flat`
    sizehint!(starts, max(16, nbytes ÷ 32))

    i = 1
    lineno = 1
    @inbounds while i <= nbytes
        # Bỏ qua khoảng trắng đầu dòng
        while i <= nbytes && _is_hws(bytes[i])
            i += 1
        end
        i > nbytes && break

        c = bytes[i]
        if c == UInt8('\n')           # Dòng rỗng: bỏ qua
            i += 1
            lineno += 1
            continue
        end
        if c == UInt8('#') || c == UInt8('%') || c == UInt8('@')  # Dòng chú thích/header SPMF: bỏ qua hết dòng
            while i <= nbytes && bytes[i] != UInt8('\n')
                i += 1
            end
            i += 1
            lineno += 1
            continue
        end

        # Đọc lần lượt các số nguyên không âm trên cùng một dòng giao dịch
        while i <= nbytes && bytes[i] != UInt8('\n')
            c = bytes[i]
            if _is_hws(c)
                i += 1
            elseif _is_digit(c)
                val = Int64(0)
                while i <= nbytes && _is_digit(bytes[i])          # Chuyển ASCII -> Int64 trực tiếp
                    val = 10 * val + Int64(bytes[i] - UInt8('0'))
                    i += 1
                end
                push!(flat, val)
            else
                throw(ArgumentError(
                    "Lỗi định dạng dữ liệu ở dòng $lineno: ký tự không hợp lệ '$(Char(c))'"))
            end
        end
        i += 1
        lineno += 1
        push!(starts, length(flat) + 1)  # Đánh dấu kết thúc giao dịch hiện tại
    end

    return _remap_transactions(flat, starts)
end

"""
    _remap_transactions(flat, starts) -> TransactionDB

Mục đích: Chuyển đổi mã item gốc (có thể thưa hoặc rất lớn) sang mã nội bộ liên tiếp `1..m` (`Int32`),
đồng thời đảm bảo mỗi giao dịch được sắp tăng dần và không chứa phần tử trùng lặp.
"""
function _remap_transactions(flat::Vector{Int64}, starts::Vector{Int})::TransactionDB
    ntx = length(starts) - 1
    if ntx == 0
        return TransactionDB(Vector{Int32}[], Int64[])
    end

    item_ids = unique!(sort(flat))    # Danh sách mã item gốc duy nhất, đã sắp tăng dần (vị trí k -> mã nội bộ k)
    m = length(item_ids)
    m <= typemax(Int32) || throw(ArgumentError("Số mặt hàng phân biệt vượt giới hạn Int32"))

    max_id = isempty(item_ids) ? Int64(0) : item_ids[end]
    transactions = Vector{Vector{Int32}}(undef, ntx)

    if max_id <= 50_000_000           # Nhánh nhanh: dùng mảng tra trực tiếp O(1) thay vì Dict
        lookup = zeros(Int32, Int(max_id) + 1)
        @inbounds for (k, id) in enumerate(item_ids)
            lookup[Int(id) + 1] = Int32(k)
        end
        @inbounds for j in 1:ntx
            s0 = starts[j]
            s1 = starts[j + 1] - 1
            len = s1 - s0 + 1
            tx = Vector{Int32}(undef, len)
            prev = Int32(0)
            already_strict = true     # Kiểm tra giao dịch đã tăng nghiêm ngặt chưa để khỏi phải sort lại
            for p in 1:len
                code = lookup[Int(flat[s0 + p - 1]) + 1]
                tx[p] = code
                if code <= prev
                    already_strict = false
                end
                prev = code
            end
            if !already_strict        # Chỉ sắp xếp & lọc trùng khi giao dịch đầu vào chưa chuẩn hóa
                sort!(tx)
                unique!(tx)
            end
            transactions[j] = tx
        end
    else                              # Nhánh dự phòng: mã item quá lớn (> 50 triệu) thì dùng Dict để tiết kiệm RAM
        orig_to_internal = Dict{Int64,Int32}()
        sizehint!(orig_to_internal, m)
        for (k, id) in enumerate(item_ids)
            orig_to_internal[id] = Int32(k)
        end
        @inbounds for j in 1:ntx
            s0 = starts[j]
            s1 = starts[j + 1] - 1
            len = s1 - s0 + 1
            tx = Vector{Int32}(undef, len)
            prev = Int32(0)
            already_strict = true
            for p in 1:len
                code = orig_to_internal[flat[s0 + p - 1]]
                tx[p] = code
                if code <= prev
                    already_strict = false
                end
                prev = code
            end
            if !already_strict
                sort!(tx)
                unique!(tx)
            end
            transactions[j] = tx
        end
    end

    return TransactionDB(transactions, item_ids)
end

"""
    read_spmf(path::AbstractString) -> TransactionDB
    read_spmf(io::IO) -> TransactionDB

Đọc CSDL giao dịch chuẩn SPMF từ đường dẫn tệp hoặc luồng `IO`.
"""
function read_spmf(path::AbstractString)::TransactionDB
    isfile(path) || throw(ArgumentError("Không tìm thấy file dữ liệu: $path"))
    return parse_spmf(read(path))
end

read_spmf(io::IO)::TransactionDB = parse_spmf(read(io))

# ---------------------------------------------------------------------------
# Ghi kết quả chuẩn SPMF (cả dạng đệm khối SPMFWriter lẫn dạng đơn lẻ write_itemset)
# ---------------------------------------------------------------------------

"""Ghi số nguyên không âm ra bộ đệm byte `buf` không cấp phát chuỗi."""
@inline function _append_uint_ascii!(buf::Vector{UInt8}, n::Integer)
    x = UInt64(n)
    if x < 10
        push!(buf, UInt8('0') + UInt8(x))
        return nothing
    end
    start = length(buf) + 1
    while x > 0
        q, r = divrem(x, UInt64(10))
        push!(buf, UInt8('0') + UInt8(r))
        x = q
    end
    # Đảo ngược các chữ số vừa ghi
    lo = start
    hi = length(buf)
    @inbounds while lo < hi
        buf[lo], buf[hi] = buf[hi], buf[lo]
        lo += 1
        hi -= 1
    end
    return nothing
end

"""
    SPMFWriter(io, db; flush_bytes = 1 << 20)

Bộ ghi tập phổ biến chuẩn SPMF có bộ đệm byte nội bộ (mặc định 1 MiB) và mã hóa trước
chuỗi byte của từng `db.item_ids`, giúp ghi hàng trăm nghìn tập nhanh hơn 6–10 lần so với
ghi từng lần gọi `print`.
"""
mutable struct SPMFWriter{T<:IO}
    io::T
    names::Vector{Vector{UInt8}}
    buf::Vector{UInt8}
    tmp::Vector{Int32}
    flush_bytes::Int
    count::Int
end

function SPMFWriter(io::T, db::TransactionDB; flush_bytes::Int = 1 << 20) where {T<:IO}
    names = [Vector{UInt8}(codeunits(string(id))) for id in db.item_ids]
    buf = UInt8[]
    sizehint!(buf, flush_bytes + 4096)
    return SPMFWriter{T}(io, names, buf, Int32[], flush_bytes, 0)
end

"""Ghi một tập phổ biến vào bộ đệm của `SPMFWriter` (bỏ qua nếu tập rỗng)."""
function write_itemset!(w::SPMFWriter, items::AbstractVector{Int32}, support::Integer)
    k = length(items)
    k == 0 && return nothing
    buf = w.buf
    names = w.names

    if k == 1
        @inbounds append!(buf, names[items[1]])
    elseif k == 2
        @inbounds begin
            a, b = items[1], items[2]
            if a <= b
                append!(buf, names[a]); push!(buf, UInt8(' ')); append!(buf, names[b])
            else
                append!(buf, names[b]); push!(buf, UInt8(' ')); append!(buf, names[a])
            end
        end
    else
        tmp = w.tmp
        resize!(tmp, k)
        copyto!(tmp, items)
        sort!(tmp)
        @inbounds begin
            append!(buf, names[tmp[1]])
            for i in 2:k
                push!(buf, UInt8(' '))
                append!(buf, names[tmp[i]])
            end
        end
    end

    append!(buf, b" #SUP: ")
    _append_uint_ascii!(buf, support)
    push!(buf, UInt8('\n'))
    w.count += 1
    length(buf) >= w.flush_bytes && flush_writer!(w)
    return nothing
end

"""Đẩy dữ liệu hiện có trong bộ đệm ra luồng `io`."""
function flush_writer!(w::SPMFWriter)
    isempty(w.buf) && return nothing
    write(w.io, w.buf)
    empty!(w.buf)
    return nothing
end

"""Đẩy nốt bộ đệm và `flush` luồng đầu ra (không đóng `io`)."""
close_writer!(w::SPMFWriter) = (flush_writer!(w); flush(w.io); nothing)

"""
    write_itemset(io::IO, items::AbstractVector{Int32}, support::Integer, db::TransactionDB[, buf])

Ghi một tập phổ biến đơn lẻ ra `io` theo định dạng SPMF `i1 i2 ... #SUP: s`.
"""
function write_itemset(io::IO, items::AbstractVector{Int32}, support::Integer,
                       db::TransactionDB, buf::Vector{Int32})
    k = length(items)
    k == 0 && return nothing
    item_ids = db.item_ids
    if k == 1
        @inbounds print(io, item_ids[items[1]], " #SUP: ", support, '\n')
        return nothing
    elseif k == 2
        @inbounds begin
            a, b = items[1], items[2]
            if a <= b
                print(io, item_ids[a], ' ', item_ids[b], " #SUP: ", support, '\n')
            else
                print(io, item_ids[b], ' ', item_ids[a], " #SUP: ", support, '\n')
            end
        end
        return nothing
    end
    resize!(buf, k)
    copyto!(buf, items)
    sort!(buf)
    @inbounds begin
        print(io, item_ids[buf[1]])
        for i in 2:k
            print(io, ' ', item_ids[buf[i]])
        end
    end
    print(io, " #SUP: ", support, '\n')
    return nothing
end

write_itemset(io::IO, items::AbstractVector{Int32}, support::Integer, db::TransactionDB) =
    write_itemset(io, items, support, db, Int32[])
