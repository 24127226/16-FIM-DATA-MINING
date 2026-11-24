# Mô-đun đọc/ghi định dạng SPMF và quy đổi ngưỡng hỗ trợ tối thiểu (minsup).
#
# Hành vi tham chiếu được kiểm chứng hộp đen với SPMF tại results/spmf_behavior.md:
#   - D04: σ_min = ceil(Int, Float64(minsup) * N); chuỗi "p%" được quy đổi thành p / 100.
#   - D05: bỏ qua dòng rỗng và dòng bắt đầu bằng '#', '%', '@'; N là số dòng còn lại.
#   - D06: xuất định dạng "i1 i2 ... #SUP: s" theo mã mặt hàng gốc tăng dần, không xuất tập rỗng.

"""
    read_spmf(io::IO) -> TransactionDB
    read_spmf(path::AbstractString) -> TransactionDB

Đọc CSDL giao dịch theo định dạng SPMF.

- Bỏ qua dòng rỗng (chỉ gồm khoảng trắng) và dòng bắt đầu bằng `#`, `%`, `@` (metadata/chú thích).
- Mỗi dòng còn lại là một giao dịch gồm các mã item nguyên (`Int64`), cách nhau bởi khoảng trắng.
- Tự sắp xếp tăng dần và loại bỏ item trùng trong mỗi giao dịch.
- Ánh xạ các mã item gốc (tăng dần) sang mã nội bộ `1..m` (`Int32`).
"""
function read_spmf(io::IO)::TransactionDB
    raw_txs = Vector{Vector{Int64}}()
    seen_items = Set{Int64}()

    for (lineno, line) in enumerate(eachline(io))
        s = strip(line)
        isempty(s) && continue
        c = first(s)
        (c == '#' || c == '%' || c == '@') && continue

        tokens = split(s)
        tx = Vector{Int64}(undef, length(tokens))
        for (idx, tok) in enumerate(tokens)
            val = tryparse(Int64, tok)
            val === nothing && throw(ArgumentError(
                "Lỗi định dạng dữ liệu ở dòng $lineno: không thể chuyển '$tok' sang số nguyên"))
            tx[idx] = val
        end
        sort!(tx)
        unique!(tx)
        for item in tx
            push!(seen_items, item)
        end
        push!(raw_txs, tx)
    end

    item_ids = sort!(collect(seen_items))
    orig_to_internal = Dict{Int64,Int32}()
    sizehint!(orig_to_internal, length(item_ids))
    for (idx, orig_id) in enumerate(item_ids)
        orig_to_internal[orig_id] = Int32(idx)
    end

    # Vì item_ids tăng dần và mỗi tx trong raw_txs đã tăng dần, không trùng,
    # nên sau khi ánh xạ sang mã nội bộ, mỗi giao dịch vẫn tăng dần và không trùng.
    transactions = Vector{Vector{Int32}}(undef, length(raw_txs))
    for (i, tx) in enumerate(raw_txs)
        mapped = Vector{Int32}(undef, length(tx))
        @inbounds for (j, orig_id) in enumerate(tx)
            mapped[j] = orig_to_internal[orig_id]
        end
        transactions[i] = mapped
    end

    return TransactionDB(transactions, item_ids)
end

function read_spmf(path::AbstractString)::TransactionDB
    isfile(path) || throw(ArgumentError("Không tìm thấy file dữ liệu: $path"))
    return open(read_spmf, path, "r")
end

"""
    parse_minsup(s::AbstractString) -> Float64

Chuyển chuỗi ngưỡng `minsup` sang tỉ lệ trong `(0, 1]`.
Chấp nhận cả dạng tỉ lệ (ví dụ `"0.4"`) lẫn phần trăm (ví dụ `"40%"`, đổi thành `40.0 / 100`
đúng như SPMF để khớp sai số Float64 ở biên).
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

Đổi ngưỡng `minsup` dạng tỉ lệ sang ngưỡng dạng đếm `σ_min = ceil(Int, Float64(minsup) * n)`
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

"""
    write_itemset(io::IO, items::AbstractVector{Int32}, support::Integer, db::TransactionDB)
    write_itemset(io::IO, items::AbstractVector{Int32}, support::Integer, db::TransactionDB, buf::Vector{Int32})

Ghi một tập phổ biến ra `io` theo đúng định dạng SPMF: `i1 i2 ... #SUP: s`.

- Bỏ qua nếu `items` rỗng (quyết định D06).
- Tự đổi mã nội bộ sang mã gốc `db.item_ids` và sắp tăng dần mà không làm thay đổi `items`.
- Bản nhận thêm `buf` tái sử dụng buffer để tránh cấp phát bộ nhớ khi ghi hàng triệu tập.
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
            a = items[1]
            b = items[2]
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

function write_itemset(io::IO, items::AbstractVector{Int32}, support::Integer, db::TransactionDB)
    return write_itemset(io, items, support, db, Int32[])
end
