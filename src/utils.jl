# Đọc/ghi định dạng SPMF, quy tắc minsup, so sánh kết quả (phần của B).
# Các quy tắc ở đây đã được kiểm chứng bằng thí nghiệm với SPMF: results/spmf_behavior.md.

# ---------------------------------------------------------------------------
# minsup
# ---------------------------------------------------------------------------

"""
    parse_minsup(s) -> Float64

Đọc ngưỡng minsup theo đúng cách SPMF hiểu:
- `"40%"` → `40 / 100` (phép chia Float64, y hệt SPMF);
- `"0.4"` → `0.4` (chuỗi không có `%` là tỉ lệ).

Ngưỡng phải nằm trong (0, 1].
"""
function parse_minsup(s::AbstractString)
    t = strip(s)
    v = if endswith(t, '%')
        parse(Float64, t[firstindex(t):prevind(t, lastindex(t))]) / 100
    else
        parse(Float64, t)
    end
    (0 < v <= 1) || throw(ArgumentError("minsup phải thuộc (0, 1] hoặc (0%, 100%], nhận được \"$s\""))
    return v
end

"""
    minsup_count(minsup, n) -> Int

Đổi minsup tỉ lệ sang số đếm: `σ_min = ceil(minsup × n)` tính bằng Float64, **y hệt SPMF**
(kể cả khi sai số số thực làm kết quả lệch khỏi giá trị toán học, ví dụ 28% của 25 cho 8).
Luôn ≥ 1.
"""
minsup_count(minsup::Real, n::Integer) = max(1, ceil(Int, Float64(minsup) * n))

# ---------------------------------------------------------------------------
# Đọc file SPMF
# ---------------------------------------------------------------------------

@inline _isspace(c::UInt8) = c == UInt8(' ') || c == UInt8('\t') || c == UInt8('\r')
@inline _isdigit(c::UInt8) = UInt8('0') <= c <= UInt8('9')

"""
    read_spmf(path) -> TransactionDB

Đọc CSDL giao dịch định dạng SPMF: mỗi dòng một giao dịch, item là số nguyên không âm.

- Bỏ qua dòng rỗng và dòng bắt đầu bằng `#`, `%`, `@` (metadata). **N là số dòng còn lại**,
  đúng như SPMF đếm.
- Chấp nhận mọi khoảng trắng (dấu cách, tab, CR); tự sắp xếp và bỏ item trùng trong mỗi giao dịch.
- Đổi mã gốc về mã nội bộ `1..m` theo thứ tự tăng dần của mã gốc.

Độ phức tạp O(tổng số item trong file).
"""
read_spmf(path::AbstractString) = parse_spmf(read(path))

"""
    parse_spmf(bytes) -> TransactionDB

Phần lõi của `read_spmf`, nhận nội dung file dạng byte.
"""
function parse_spmf(bytes::AbstractVector{UInt8})
    flat = Int64[]            # mọi item của mọi giao dịch, nối liên tiếp
    starts = Int[1]           # giao dịch j chiếm flat[starts[j] : starts[j+1]-1]
    n = length(bytes)
    i = 1
    line = 1
    @inbounds while i <= n
        # bỏ khoảng trắng đầu dòng
        while i <= n && _isspace(bytes[i])
            i += 1
        end
        if i > n
            break
        end
        c = bytes[i]
        if c == UInt8('\n')                          # dòng rỗng
            i += 1; line += 1
            continue
        end
        if c == UInt8('#') || c == UInt8('%') || c == UInt8('@')   # metadata, chú thích
            while i <= n && bytes[i] != UInt8('\n')
                i += 1
            end
            i += 1; line += 1
            continue
        end
        # một dòng giao dịch
        while i <= n && bytes[i] != UInt8('\n')
            c = bytes[i]
            if _isspace(c)
                i += 1
            elseif _isdigit(c)
                v = Int64(0)
                while i <= n && _isdigit(bytes[i])
                    v = 10v + (bytes[i] - UInt8('0'))
                    i += 1
                end
                push!(flat, v)
            else
                throw(ArgumentError("dòng $line: ký tự không hợp lệ '$(Char(c))' (item phải là số nguyên không âm)"))
            end
        end
        i += 1; line += 1
        push!(starts, length(flat) + 1)
    end
    return _remap(flat, starts)
end

"""Đổi mã gốc → mã nội bộ 1..m (tăng dần theo mã gốc), sắp xếp và bỏ trùng từng giao dịch."""
function _remap(flat::Vector{Int64}, starts::Vector{Int})
    ntx = length(starts) - 1
    item_ids = unique!(sort(flat))
    m = length(item_ids)
    m <= typemax(Int32) || throw(ArgumentError("quá nhiều item phân biệt"))
    maxid = isempty(item_ids) ? Int64(0) : item_ids[end]
    transactions = Vector{Vector{Int32}}(undef, ntx)
    if maxid <= 50_000_000          # mã gốc đủ nhỏ: dùng mảng tra trực tiếp (nhanh)
        lookup = zeros(Int32, maxid + 1)
        for (k, id) in enumerate(item_ids)
            lookup[id + 1] = Int32(k)
        end
        @inbounds for j in 1:ntx
            t = Vector{Int32}(undef, starts[j+1] - starts[j])
            for (p, q) in enumerate(starts[j]:starts[j+1]-1)
                t[p] = lookup[flat[q] + 1]
            end
            transactions[j] = _sorted_unique!(t)
        end
    else                            # mã gốc rất lớn: dùng bảng băm
        index = Dict{Int64,Int32}(id => Int32(k) for (k, id) in enumerate(item_ids))
        for j in 1:ntx
            t = Int32[index[flat[q]] for q in starts[j]:starts[j+1]-1]
            transactions[j] = _sorted_unique!(t)
        end
    end
    return TransactionDB(transactions, item_ids)
end

function _sorted_unique!(t::Vector{Int32})
    issorted(t) || sort!(t)
    # bỏ phần tử trùng (đã sắp xếp nên phần tử trùng đứng cạnh nhau)
    w = 0
    @inbounds for r in eachindex(t)
        if w == 0 || t[r] != t[w]
            w += 1
            t[w] = t[r]
        end
    end
    return resize!(t, w)
end

# ---------------------------------------------------------------------------
# Ghi kết quả theo định dạng SPMF
# ---------------------------------------------------------------------------

"""
    write_itemset(io, items, support, db)

Ghi một tập phổ biến thành một dòng `i1 i2 … #SUP: s` theo **mã gốc tăng dần**.
`items` là mã nội bộ (có thể chưa sắp xếp). Bản đơn giản; khi ghi nhiều tập hãy dùng `SPMFWriter`.
"""
function write_itemset(io::IO, items::AbstractVector{<:Integer}, support::Integer, db::TransactionDB)
    original = sort!([db.item_ids[x] for x in items])
    for x in original
        print(io, x, ' ')
    end
    print(io, "#SUP: ", support, '\n')
    return nothing
end

"""
    SPMFWriter(io, db)

Ghi tập phổ biến theo định dạng SPMF với bộ đệm 1 MiB: nhanh khi có hàng triệu tập.
Dùng `write_itemset!` cho từng tập và `close_writer!` (hoặc `flush_writer!`) ở cuối.
"""
mutable struct SPMFWriter{T<:IO}
    io::T
    buf::Vector{UInt8}
    names::Vector{Vector{UInt8}}   # names[k] = chữ số của mã gốc ứng với mã nội bộ k
    tmp::Vector{Int32}
    count::Int
end

function SPMFWriter(io::IO, db::TransactionDB)
    buf = UInt8[]
    sizehint!(buf, 1 << 20)
    return SPMFWriter(io, buf, [Vector{UInt8}(string(x)) for x in db.item_ids], Int32[], 0)
end

@inline function _append_int!(buf::Vector{UInt8}, v::Integer)
    if v == 0
        push!(buf, UInt8('0'))
        return
    end
    start = length(buf) + 1
    while v > 0
        push!(buf, UInt8('0') + UInt8(v % 10))
        v ÷= 10
    end
    reverse!(buf, start, length(buf))
    return
end

"""Ghi một tập (mã nội bộ, có thể chưa sắp xếp) và support của nó."""
function write_itemset!(w::SPMFWriter, items::AbstractVector{Int32}, support::Integer)
    tmp = w.tmp
    resize!(tmp, length(items))
    copyto!(tmp, items)
    sort!(tmp)                      # mã nội bộ tăng dần ⇔ mã gốc tăng dần
    buf = w.buf
    @inbounds for x in tmp
        append!(buf, w.names[x])
        push!(buf, UInt8(' '))
    end
    append!(buf, b"#SUP: ")
    _append_int!(buf, support)
    push!(buf, UInt8('\n'))
    w.count += 1
    length(buf) >= (1 << 20) && flush_writer!(w)
    return nothing
end

"""Đẩy phần còn trong bộ đệm ra `io`."""
function flush_writer!(w::SPMFWriter)
    write(w.io, w.buf)
    empty!(w.buf)
    return nothing
end

"""Ghi nốt bộ đệm và `flush` luồng ra; gọi một lần sau khi ghi xong tập cuối cùng (không đóng `io`)."""
close_writer!(w::SPMFWriter) = (flush_writer!(w); flush(w.io); nothing)

"""
    mine_to_file(db, minsup, path, cfg; stats = nothing, maxlen = typemax(Int)) -> Int

Khai thác và ghi kết quả ra file SPMF (`path == "-"` thì in ra màn hình). Trả về số tập phổ biến.
"""
function mine_to_file(db::TransactionDB, minsup::Integer, path::AbstractString,
                      cfg::EclatConfig = DEFAULT_CONFIG; stats = nothing, maxlen::Integer = typemax(Int))
    if path == "-"
        w = SPMFWriter(stdout, db)
        eclat!((items, s) -> write_itemset!(w, items, s), db, minsup, cfg; stats = stats, maxlen = maxlen)
        close_writer!(w)
        return w.count
    end
    open(path, "w") do io
        w = SPMFWriter(io, db)
        eclat!((items, s) -> write_itemset!(w, items, s), db, minsup, cfg; stats = stats, maxlen = maxlen)
        close_writer!(w)
        return w.count
    end
end

# ---------------------------------------------------------------------------
# Đọc kết quả và so sánh
# ---------------------------------------------------------------------------

"""
    load_itemsets(path) -> Dict{Vector{Int64},Int}

Đọc file kết quả định dạng SPMF (của SPMF hoặc của nhóm). Khóa là mã gốc đã sắp tăng dần.
"""
function load_itemsets(path::AbstractString)
    res = Dict{Vector{Int64},Int}()
    for line in eachline(path)
        s = strip(line)
        (isempty(s) || startswith(s, '@')) && continue
        k = findfirst("#SUP:", s)
        k === nothing && throw(ArgumentError("dòng không có #SUP: \"$s\""))
        items = sort!([parse(Int64, x) for x in split(s[1:first(k)-1])])
        res[items] = parse(Int, strip(s[last(k)+1:end]))
    end
    return res
end

"""
    compare_itemsets(ours, ref) -> NamedTuple

So hai tập kết quả. Tỉ lệ khớp (KE_HOACH_DU_AN.md, mục 7.2) =
số tập có mặt ở cả hai với **cùng support** ÷ số tập ở hợp của hai bên.
"""
function compare_itemsets(ours::AbstractDict, ref::AbstractDict)
    matched = 0
    diff_support = 0
    for (k, v) in ours
        w = get(ref, k, nothing)
        if w !== nothing
            w == v ? (matched += 1) : (diff_support += 1)
        end
    end
    common = matched + diff_support
    only_ours = length(ours) - common
    only_ref = length(ref) - common
    union = length(ours) + only_ref
    rate = union == 0 ? 1.0 : matched / union
    return (n_ours = length(ours), n_ref = length(ref), matched = matched,
            diff_support = diff_support, only_ours = only_ours, only_ref = only_ref, rate = rate)
end

# ---- Dấu vân tay: so sánh kết quả rất lớn mà không cần nạp vào bộ nhớ ----

@inline function _splitmix64(x::UInt64)
    x += 0x9e3779b97f4a7c15
    x = (x ⊻ (x >> 30)) * 0xbf58476d1ce4e5b9
    x = (x ⊻ (x >> 27)) * 0x94d049bb133111eb
    return x ⊻ (x >> 31)
end

"""Băm 64-bit ổn định (không phụ thuộc phiên bản Julia) của một tập đã sắp xếp cùng support."""
function itemset_hash(items::AbstractVector{<:Integer}, support::Integer)
    h = 0x6a09e667f3bcc909
    for x in items
        h = _splitmix64(h ⊻ UInt64(x))
    end
    return _splitmix64(h ⊻ (UInt64(support) << 1 | 0x01))
end

"""
    fingerprint(path) -> (count, hash)

Dấu vân tay **không phụ thuộc thứ tự dòng** của file kết quả SPMF: số tập và tổng (mod 2⁶⁴)
các giá trị băm. Hai file cho cùng dấu vân tay thì gần như chắc chắn chứa cùng các tập với cùng support.
"""
function fingerprint(path::AbstractString)
    count = 0
    acc = UInt64(0)
    items = Int64[]
    for line in eachline(path)
        s = strip(line)
        (isempty(s) || startswith(s, '@')) && continue
        k = findfirst("#SUP:", s)
        empty!(items)
        for x in split(view(s, 1:first(k)-1))
            push!(items, parse(Int64, x))
        end
        sort!(items)
        acc += itemset_hash(items, parse(Int, strip(view(s, last(k)+1:lastindex(s)))))
        count += 1
    end
    return (count = count, hash = acc)
end
