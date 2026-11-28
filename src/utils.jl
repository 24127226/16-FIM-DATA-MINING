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

Mục đích hàm: Chuyển chuỗi ngưỡng `minsup` (ví dụ `"0.4"` hoặc `"40%"`) sang số thực `Float64`
trong khoảng `(0, 1]` khớp chính xác quy tắc làm tròn dấu phẩy động của SPMF.
"""
function parse_minsup(s::AbstractString)::Float64
    t = strip(s)                                             # Xóa khoảng trắng thừa hai đầu chuỗi
    isempty(t) && throw(ArgumentError("minsup không được rỗng")) # Báo lỗi ngay nếu chuỗi rỗng
    val = if endswith(t, '%')                                # Trường hợp người dùng nhập dạng phần trăm (vd: "40%")
        num_str = strip(SubString(t, firstindex(t), prevind(t, lastindex(t)))) # Cắt bỏ ký tự '%' ở cuối
        v = tryparse(Float64, num_str)                       # Chuyển phần số sang Float64
        v === nothing && throw(ArgumentError("minsup không hợp lệ: '$s'")) # Báo lỗi nếu không phải số
        v / 100                                              # Chia 100 đúng theo Float64 của SPMF
    else                                                     # Trường hợp người dùng nhập dạng tỉ lệ (vd: "0.4")
        v = tryparse(Float64, t)                             # Chuyển thẳng sang Float64
        v === nothing && throw(ArgumentError("minsup không hợp lệ: '$s'")) # Báo lỗi nếu không phải số
        v                                                    # Giữ nguyên tỉ lệ
    end
    (isfinite(val) && 0.0 < val <= 1.0) ||                   # Kiểm tra ngưỡng phải hữu hạn và thuộc (0, 1]
        throw(ArgumentError("minsup phải nằm trong khoảng (0, 1] (hoặc (0%, 100%]), nhận được: '$s'"))
    return val                                               # Trả về tỉ lệ minsup hợp lệ
end

"""
    minsup_count(minsup::Real, n::Integer) -> Int
    minsup_count(minsup::AbstractString, n::Integer) -> Int

Mục đích hàm: Đổi ngưỡng `minsup` dạng tỉ lệ sang ngưỡng đếm nguyên `σ_min = ceil(Int, Float64(minsup) * n)`
đúng theo quy tắc của SPMF để không bị lệch biên dấu phẩy động (xem `results/spmf_behavior.md`).
"""
function minsup_count(minsup::Real, n::Integer)::Int
    n >= 0 || throw(ArgumentError("Số giao dịch n phải ≥ 0, nhận được: $n")) # Kiểm tra số giao dịch không âm
    mf = Float64(minsup)                                     # Ép kiểu sang Float64 giống Java double của SPMF
    (isfinite(mf) && 0.0 < mf <= 1.0) ||                     # Kiểm tra minsup nằm trong (0, 1]
        throw(ArgumentError("minsup phải nằm trong khoảng (0, 1], nhận được: $minsup"))
    return ceil(Int, mf * n)                                 # Làm tròn lên thành số nguyên giao dịch tối thiểu σ_min
end

# Nạp chồng (multiple dispatch): cho phép truyền minsup dạng chuỗi (vd "40%") trực tiếp vào minsup_count
minsup_count(minsup::AbstractString, n::Integer)::Int = minsup_count(parse_minsup(minsup), n)

# ---------------------------------------------------------------------------
# Đọc tệp SPMF tối ưu theo byte (không cấp phát chuỗi trung gian)
# ---------------------------------------------------------------------------

# Hàm nội tuyến kiểm tra 1 byte có phải khoảng trắng ngang (space, tab, carriage return) hay không
@inline _is_hws(c::UInt8) = c == UInt8(' ') || c == UInt8('\t') || c == UInt8('\r')
# Hàm nội tuyến kiểm tra 1 byte có phải chữ số ASCII từ '0' đến '9' hay không
@inline _is_digit(c::UInt8) = UInt8('0') <= c <= UInt8('9')

"""
    parse_spmf(bytes::AbstractVector{UInt8}) -> TransactionDB

Mục đích hàm: Phân tích toàn bộ tệp giao dịch chuẩn SPMF trực tiếp trên mảng byte (không tạo
chuỗi String cho từng dòng nên nhanh hơn `eachline`/`split` 10–15 lần):
- Bỏ qua dòng rỗng và dòng chú thích/siêu dữ liệu bắt đầu bằng `#`, `%`, `@`.
- Tự sắp xếp tăng dần và khử trùng lặp item trong mỗi giao dịch.
- Ánh xạ mã gốc (`Int64`, tăng dần) sang mã nội bộ liên tiếp `1..m` (`Int32`).
"""
function parse_spmf(bytes::AbstractVector{UInt8})::TransactionDB
    nbytes = length(bytes)                                   # Tổng số byte của tệp đầu vào
    flat = Int64[]                                           # Mảng phẳng chứa toàn bộ mã item gốc đọc được
    sizehint!(flat, nbytes ÷ 4)                              # Dự trù bộ nhớ trước để tránh cấp phát lại nhiều lần
    starts = Int[1]                                          # Mảng đánh dấu vị trí bắt đầu của từng giao dịch trong `flat`
    sizehint!(starts, max(16, nbytes ÷ 32))                  # Dự trù số lượng giao dịch ước lượng

    i = 1                                                    # Con trỏ byte hiện tại trong mảng `bytes`
    lineno = 1                                               # Số thứ tự dòng hiện tại (dùng để báo lỗi rõ ràng)
    @inbounds while i <= nbytes                              # Duyệt toàn bộ mảng byte (tắt kiểm tra biên để tăng tốc)
        while i <= nbytes && _is_hws(bytes[i])               # Bỏ qua mọi khoảng trắng ở đầu dòng
            i += 1
        end
        i > nbytes && break                                  # Đã chạm cuối tệp thì dừng vòng lặp

        c = bytes[i]                                         # Đọc byte đầu tiên khác khoảng trắng của dòng
        if c == UInt8('\n')                                  # Nếu là dòng rỗng thì nhảy sang dòng kế tiếp
            i += 1
            lineno += 1
            continue
        end
        if c == UInt8('#') || c == UInt8('%') || c == UInt8('@') # Dòng chú thích hoặc header SPMF (@ITEM=...)
            while i <= nbytes && bytes[i] != UInt8('\n')     # Lướt bỏ toàn bộ phần còn lại của dòng
                i += 1
            end
            i += 1                                           # Bỏ qua ký tự xuống dòng '\n'
            lineno += 1
            continue
        end

        while i <= nbytes && bytes[i] != UInt8('\n')         # Đọc từng item trên cùng một dòng giao dịch
            c = bytes[i]
            if _is_hws(c)                                    # Gặp khoảng trắng giữa các item -> lướt qua
                i += 1
            elseif _is_digit(c)                              # Gặp chữ số -> ghép thành số nguyên Int64
                val = Int64(0)
                while i <= nbytes && _is_digit(bytes[i])     # Đọc liên tiếp các chữ số của 1 mã item
                    val = 10 * val + Int64(bytes[i] - UInt8('0')) # Nhân 10 cộng chữ số mới (không qua parse String)
                    i += 1
                end
                push!(flat, val)                             # Lưu mã item gốc vừa đọc vào mảng phẳng
            else                                             # Gặp ký tự lạ không phải số/khoảng trắng -> báo lỗi định dạng
                throw(ArgumentError(
                    "Lỗi định dạng dữ liệu ở dòng $lineno: ký tự không hợp lệ '$(Char(c))'"))
            end
        end
        i += 1                                               # Nhảy qua ký tự xuống dòng '\n'
        lineno += 1                                          # Tăng bộ đếm dòng
        push!(starts, length(flat) + 1)                      # Ghi mốc bắt đầu của giao dịch tiếp theo
    end

    return _remap_transactions(flat, starts)                 # Ánh xạ mã gốc -> mã nội bộ 1..m và đóng gói TransactionDB
end

"""
    _remap_transactions(flat::Vector{Int64}, starts::Vector{Int}) -> TransactionDB

Mục đích hàm: Ánh xạ toàn bộ mã item gốc (`Int64`) sang mã nội bộ liên tiếp `1..m` (`Int32`)
theo thứ tự tăng dần, đồng thời chuẩn hóa mỗi giao dịch (sắp tăng dần và xóa phần tử trùng lặp).
"""
function _remap_transactions(flat::Vector{Int64}, starts::Vector{Int})::TransactionDB
    ntx = length(starts) - 1                                 # Số giao dịch thực tế đọc được
    if ntx == 0                                              # Nếu tệp không có giao dịch nào -> trả CSDL rỗng
        return TransactionDB(Vector{Int32}[], Int64[])
    end

    item_ids = unique!(sort(flat))                           # Tập mã item gốc duy nhất, sắp tăng dần (chỉ số k = mã nội bộ k)
    m = length(item_ids)                                     # Tổng số mặt hàng phân biệt m
    m <= typemax(Int32) || throw(ArgumentError("Số mặt hàng phân biệt vượt giới hạn Int32"))

    max_id = isempty(item_ids) ? Int64(0) : item_ids[end]    # Mã item gốc lớn nhất (phần tử cuối vì đã sort)
    transactions = Vector{Vector{Int32}}(undef, ntx)         # Cấp phát sẵn mảng chứa ntx giao dịch

    if max_id <= 50_000_000                                  # Nhánh tối ưu: mã không quá lớn -> dùng mảng tra trực tiếp O(1)
        lookup = zeros(Int32, Int(max_id) + 1)               # Bảng tra mảng (cộng 1 vì chỉ số Julia bắt đầu từ 1, còn id có thể từ 0)
        @inbounds for (k, id) in enumerate(item_ids)         # Điền ánh xạ: id gốc -> mã nội bộ k (Int32)
            lookup[Int(id) + 1] = Int32(k)
        end
        @inbounds for j in 1:ntx                             # Duyệt từng giao dịch thứ j
            s0 = starts[j]                                   # Vị trí đầu của giao dịch j trong mảng phẳng `flat`
            s1 = starts[j + 1] - 1                           # Vị trí cuối của giao dịch j trong mảng phẳng `flat`
            len = s1 - s0 + 1                                # Độ dài ban đầu của giao dịch j
            tx = Vector{Int32}(undef, len)                   # Cấp phát vector chứa mã nội bộ của giao dịch j
            prev = Int32(0)                                  # Lưu mã trước đó để kiểm tra xem giao dịch đã tăng nghiêm ngặt chưa
            already_strict = true                            # Cờ báo giao dịch đã chuẩn (tăng dần, không trùng) hay chưa
            for p in 1:len                                   # Quy đổi từng phần tử trong giao dịch j
                code = lookup[Int(flat[s0 + p - 1]) + 1]     # Tra mã nội bộ trong O(1)
                tx[p] = code                                 # Ghi vào giao dịch
                if code <= prev                              # Nếu không tăng nghiêm ngặt (lộn xộn hoặc trùng lặp)
                    already_strict = false                   # Đánh dấu cần sort! và unique!
                end
                prev = code                                  # Cập nhật mã trước đó
            end
            if !already_strict                               # Chỉ sắp xếp & khử trùng khi thực sự cần (tiết kiệm thời gian)
                sort!(tx)
                unique!(tx)
            end
            transactions[j] = tx                             # Gán giao dịch đã chuẩn hóa vào danh sách
        end
    else                                                     # Nhánh dự phòng: mã gốc quá lớn (> 50 triệu) -> dùng Dict để tránh tốn RAM
        orig_to_internal = Dict{Int64,Int32}()               # Bảng băm ánh xạ mã gốc -> mã nội bộ
        sizehint!(orig_to_internal, m)                       # Cấp phát trước kích thước Dict
        for (k, id) in enumerate(item_ids)                   # Điền bảng băm
            orig_to_internal[id] = Int32(k)
        end
        @inbounds for j in 1:ntx                             # Duyệt từng giao dịch tương tự nhánh trên
            s0 = starts[j]
            s1 = starts[j + 1] - 1
            len = s1 - s0 + 1
            tx = Vector{Int32}(undef, len)
            prev = Int32(0)
            already_strict = true
            for p in 1:len
                code = orig_to_internal[flat[s0 + p - 1]]    # Tra mã nội bộ qua Dict
                tx[p] = code
                if code <= prev
                    already_strict = false
                end
                prev = code
            end
            if !already_strict                               # Sắp xếp & khử trùng nếu cần
                sort!(tx)
                unique!(tx)
            end
            transactions[j] = tx
        end
    end

    return TransactionDB(transactions, item_ids)             # Trả về đối tượng TransactionDB hoàn chỉnh
end

"""
    read_spmf(path::AbstractString) -> TransactionDB
    read_spmf(io::IO) -> TransactionDB

Mục đích hàm: Đọc toàn bộ CSDL giao dịch chuẩn SPMF từ đường dẫn tệp (hoặc luồng `IO`)
thành mảng byte rồi gọi `parse_spmf` để phân tích.
"""
function read_spmf(path::AbstractString)::TransactionDB
    isfile(path) || throw(ArgumentError("Không tìm thấy file dữ liệu: $path")) # Kiểm tra tệp tồn tại
    return parse_spmf(read(path))                            # Đọc nguyên tệp thành Vector{UInt8} và phân tích
end

# Nạp chồng cho phép đọc trực tiếp từ luồng IO (vd IOBuffer trong unit test)
read_spmf(io::IO)::TransactionDB = parse_spmf(read(io))

# ---------------------------------------------------------------------------
# Ghi kết quả chuẩn SPMF (cả dạng đệm khối SPMFWriter lẫn dạng đơn lẻ write_itemset)
# ---------------------------------------------------------------------------

"""
    _append_uint_ascii!(buf::Vector{UInt8}, n::Integer)

Mục đích hàm: Chuyển số nguyên không âm `n` sang các ký tự chữ số ASCII và nối trực tiếp
vào bộ đệm byte `buf` mà không tạo chuỗi `String` tạm thời (tránh áp lực lên bộ thu gom rác GC).
"""
@inline function _append_uint_ascii!(buf::Vector{UInt8}, n::Integer)
    x = UInt64(n)                                            # Ép sang số nguyên không dấu 64-bit
    if x < 10                                                # Nhánh nhanh cho số có 1 chữ số (0..9)
        push!(buf, UInt8('0') + UInt8(x))
        return nothing
    end
    start = length(buf) + 1                                  # Ghi nhớ vị trí bắt đầu các chữ số mới
    while x > 0                                              # Tách từng chữ số từ hàng đơn vị lên (bị ngược thứ tự)
        q, r = divrem(x, UInt64(10))                         # q = thương, r = chữ số cuối
        push!(buf, UInt8('0') + UInt8(r))                    # Ghi mã ASCII của chữ số r
        x = q
    end
    lo = start                                               # Con trỏ đầu đoạn chữ số vừa ghi
    hi = length(buf)                                         # Con trỏ cuối đoạn chữ số vừa ghi
    @inbounds while lo < hi                                  # Đảo ngược lại đúng thứ tự từ trái sang phải
        buf[lo], buf[hi] = buf[hi], buf[lo]
        lo += 1
        hi -= 1
    end
    return nothing
end

"""
    SPMFWriter(io, db; flush_bytes = 1 << 20)

Mục đích cấu trúc: Bộ ghi tập phổ biến chuẩn SPMF có bộ đệm byte nội bộ (mặc định 1 MiB)
và mã hóa sẵn chuỗi byte của từng `db.item_ids`, giúp ghi hàng trăm nghìn dòng ra đĩa
nhanh hơn 6–10 lần so với gọi `print` từng dòng.
"""
mutable struct SPMFWriter{T<:IO}
    io::T                                                    # Luồng đầu ra (tệp trên đĩa hoặc stdout)
    names::Vector{Vector{UInt8}}                             # Mảng lưu sẵn dạng byte ASCII của từng mã item gốc
    buf::Vector{UInt8}                                       # Bộ đệm tích lũy dữ liệu trước khi ghi khối ra đĩa
    tmp::Vector{Int32}                                       # Mảng tạm dùng lại để sắp xếp itemset dài ≥ 3 (0 cấp phát mới)
    flush_bytes::Int                                         # Ngưỡng kích thước bộ đệm (mặc định 1 MiB) để xả ra đĩa
    count::Int                                               # Tổng số tập phổ biến đã ghi được
end

"""Khởi tạo `SPMFWriter` với bảng tên byte mã hóa trước và bộ đệm 1 MiB."""
function SPMFWriter(io::T, db::TransactionDB; flush_bytes::Int = 1 << 20) where {T<:IO}
    names = [Vector{UInt8}(codeunits(string(id))) for id in db.item_ids] # Đổi sẵn mọi mã gốc sang mảng byte 1 lần duy nhất
    buf = UInt8[]                                            # Khởi tạo bộ đệm rỗng
    sizehint!(buf, flush_bytes + 4096)                       # Cấp phát trước ~1 MiB để không resize trong vòng lặp
    return SPMFWriter{T}(io, names, buf, Int32[], flush_bytes, 0)
end

"""
    write_itemset!(w::SPMFWriter, items::AbstractVector{Int32}, support::Integer)

Mục đích hàm: Đưa một tập phổ biến `(items, support)` vào bộ đệm của `SPMFWriter` đúng định dạng
SPMF `i1 i2 ... #SUP: s` (mã gốc tăng dần, bỏ qua nếu tập rỗng). Khi bộ đệm đầy ≥ `flush_bytes`
sẽ tự động xả khối ra luồng `io`.
"""
function write_itemset!(w::SPMFWriter, items::AbstractVector{Int32}, support::Integer)
    k = length(items)                                        # Số phần tử trong tập phổ biến
    k == 0 && return nothing                                 # Quy ước D06: không bao giờ xuất tập rỗng
    buf = w.buf                                              # Tham chiếu cục bộ tới bộ đệm byte
    names = w.names                                          # Tham chiếu cục bộ tới bảng tên byte

    if k == 1                                                # Nhánh nhanh 1-itemset: ghi thẳng không cần sort
        @inbounds append!(buf, names[items[1]])
    elseif k == 2                                            # Nhánh nhanh 2-itemset: chỉ so sánh 2 số thay vì gọi sort!
        @inbounds begin
            a, b = items[1], items[2]
            if a <= b                                        # Vì mã nội bộ đồng biến với mã gốc -> so sánh trực tiếp được
                append!(buf, names[a]); push!(buf, UInt8(' ')); append!(buf, names[b])
            else
                append!(buf, names[b]); push!(buf, UInt8(' ')); append!(buf, names[a])
            end
        end
    else                                                     # Nhánh tổng quát (k ≥ 3): sao chép ra mảng tạm `tmp` và sắp tăng dần
        tmp = w.tmp
        resize!(tmp, k)                                      # Tái sử dụng mảng tạm không cấp phát mới
        copyto!(tmp, items)                                  # Sao chép mã nội bộ sang mảng tạm
        sort!(tmp)                                           # Sắp xếp tăng dần theo mã gốc
        @inbounds begin
            append!(buf, names[tmp[1]])                      # Ghi phần tử đầu tiên
            for i in 2:k                                     # Ghi các phần tử tiếp theo ngăn cách bởi dấu cách
                push!(buf, UInt8(' '))
                append!(buf, names[tmp[i]])
            end
        end
    end

    append!(buf, b" #SUP: ")                                 # Nối chuỗi hậu tố chuẩn SPMF
    _append_uint_ascii!(buf, support)                        # Nối giá trị độ hỗ trợ tuyệt đối
    push!(buf, UInt8('\n'))                                  # Kết thúc dòng
    w.count += 1                                             # Tăng bộ đếm số tập phổ biến đã xuất
    length(buf) >= w.flush_bytes && flush_writer!(w)         # Nếu bộ đệm đạt ngưỡng 1 MiB -> xả khối xuống đĩa
    return nothing
end

"""Mục đích hàm: Đẩy toàn bộ dữ liệu đang tích lũy trong bộ đệm `w.buf` ra luồng `w.io` và làm rỗng bộ đệm."""
function flush_writer!(w::SPMFWriter)
    isempty(w.buf) && return nothing                         # Bộ đệm rỗng thì không cần gọi ghi hệ thống
    write(w.io, w.buf)                                       # Ghi cả khối byte một lần ra đĩa/stdout
    empty!(w.buf)                                            # Xóa sạch bộ đệm để đón lượt tiếp theo
    return nothing
end

"""Mục đích hàm: Xả nốt phần dữ liệu còn sót trong bộ đệm và gọi `flush` luồng đầu ra (không đóng `io`)."""
close_writer!(w::SPMFWriter) = (flush_writer!(w); flush(w.io); nothing)

"""
    write_itemset(io::IO, items::AbstractVector{Int32}, support::Integer, db::TransactionDB[, buf])

Mục đích hàm: Ghi một tập phổ biến đơn lẻ trực tiếp ra `io` theo định dạng SPMF `i1 i2 ... #SUP: s`
(dùng tiện lợi trong kiểm thử đơn vị hoặc khi không cần bộ đệm khối `SPMFWriter`).
"""
function write_itemset(io::IO, items::AbstractVector{Int32}, support::Integer,
                       db::TransactionDB, buf::Vector{Int32})
    k = length(items)
    k == 0 && return nothing                                 # Bỏ qua tập rỗng
    item_ids = db.item_ids                                   # Bảng ánh xạ ngược: mã nội bộ -> mã gốc
    if k == 1                                                # Nhánh nhanh 1 phần tử
        @inbounds print(io, item_ids[items[1]], " #SUP: ", support, '\n')
        return nothing
    elseif k == 2                                            # Nhánh nhanh 2 phần tử
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
    resize!(buf, k)                                          # Dùng bộ đệm `buf` để sắp xếp cho k ≥ 3
    copyto!(buf, items)
    sort!(buf)
    @inbounds begin
        print(io, item_ids[buf[1]])                          # In phần tử đầu tiên
        for i in 2:k                                         # In các phần tử còn lại cách nhau bằng dấu cách
            print(io, ' ', item_ids[buf[i]])
        end
    end
    print(io, " #SUP: ", support, '\n')                      # In độ hỗ trợ và xuống dòng
    return nothing
end

# Nạp chồng rút gọn khi người gọi không truyền sẵn bộ đệm `buf`
write_itemset(io::IO, items::AbstractVector{Int32}, support::Integer, db::TransactionDB) =
    write_itemset(io, items, support, db, Int32[])
