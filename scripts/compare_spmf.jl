# Công cụ chuẩn hóa và đối chiếu tệp kết quả khai thác với cài đặt tham chiếu SPMF.
#
# Hỗ trợ nạp trực tiếp trong bộ kiểm thử hoặc thực thi độc lập:
#   julia --project=. scripts/compare_spmf.jl [--fingerprint] <file_nhom> <file_spmf>
#
# Mã thoát khi thực thi CLI:
#   0  khớp hoàn toàn 100%
#   1  phát hiện sai lệch hoặc lỗi tham số

using SHA

"""Kết quả so sánh chi tiết hai tập kết quả khai thác."""
struct CompareResult
    mode::Symbol            # :exact hoặc :fingerprint
    n_ours::Int
    n_ref::Int
    n_match::Int
    only_ours::Int
    only_ref::Int
    diff_support::Int
    match_pct::Float64
    exact_match::Bool
    hash_ours::UInt64
    hash_ref::UInt64
end

"""
    parse_spmf_output_line(line) -> Union{Nothing, Tuple{Vector{Int64}, Int}}

Phân tích một dòng output chuẩn SPMF dạng `i1 i2 ... #SUP: s`.
Trả về `(items_sorted, support)` hoặc `nothing` nếu dòng rỗng.
"""
function parse_spmf_output_line(line::AbstractString)
    s = strip(line)
    (isempty(s) || startswith(s, '@')) && return nothing
    marker = findfirst("#SUP:", s)
    marker === nothing && throw(ArgumentError("Dòng output không chứa '#SUP:': $line"))

    items_part = strip(s[firstindex(s):prevind(s, first(marker))])
    sup_part = strip(s[nextind(s, last(marker)):lastindex(s)])
    isempty(items_part) && throw(ArgumentError("Dòng output thiếu item: $line"))

    support = tryparse(Int, sup_part)
    support === nothing && throw(ArgumentError("Không đọc được support trong dòng: $line"))

    tokens = split(items_part)
    items = Vector{Int64}(undef, length(tokens))
    for (i, tok) in enumerate(tokens)
        v = tryparse(Int64, tok)
        v === nothing && throw(ArgumentError("Mã item không hợp lệ '$tok' trong dòng: $line"))
        items[i] = v
    end
    sort!(items)
    return (items, support)
end

"""Đọc file output SPMF vào `Dict{Vector{Int64}, Int}` (không phụ thuộc thứ tự dòng hay item)."""
function load_itemsets_file(path::AbstractString)::Dict{Vector{Int64},Int}
    res = Dict{Vector{Int64},Int}()
    open(path, "r") do io
        for (lineno, line) in enumerate(eachline(io))
            parsed = parse_spmf_output_line(line)
            parsed === nothing && continue
            items, sup = parsed
            if haskey(res, items)
                throw(ArgumentError("Tập phổ biến bị trùng ở dòng $lineno trong $path: $items"))
            end
            res[items] = sup
        end
    end
    return res
end

"""
    fingerprint_file(path) -> Tuple{Int, UInt64}

Tính dấu vân tay (fingerprint) cho file output lớn (KE_HOACH_DU_AN.md, mục 7.1):
chuẩn hóa từng dòng (item tăng dần + `#SUP: s`), băm SHA-256, lấy 64 bit đầu rồi cộng dồn
modulo 2^64. Độc lập hoàn toàn với thứ tự dòng và thứ tự item trong dòng.
"""
function fingerprint_file(path::AbstractString)::Tuple{Int,UInt64}
    n_lines = 0
    hash_sum = UInt64(0)
    buf = IOBuffer()
    open(path, "r") do io
        for line in eachline(io)
            parsed = parse_spmf_output_line(line)
            parsed === nothing && continue
            items, sup = parsed
            n_lines += 1
            truncate(buf, 0)
            @inbounds begin
                print(buf, items[1])
                for i in 2:length(items)
                    print(buf, ' ', items[i])
                end
            end
            print(buf, " #SUP: ", sup)
            digest = sha256(take!(buf))
            h = reinterpret(UInt64, digest[1:8])[1]
            hash_sum += h
        end
    end
    return (n_lines, hash_sum)
end

"""
    compare_dicts(ours, ref) -> CompareResult

So sánh chi tiết hai `Dict` kết quả theo đúng định nghĩa tỉ lệ khớp ở mục 7.2:
`tỉ lệ khớp = |{X ∈ F_nhóm ∩ F_SPMF : σ_nhóm(X) = σ_SPMF(X)}| / |F_nhóm ∪ F_SPMF| × 100%`.
"""
function compare_dicts(ours::AbstractDict{Vector{T},Int},
                       ref::AbstractDict{Vector{T},Int}) where {T<:Integer}
    n_match = 0
    only_ours = 0
    diff_support = 0

    for (k, s_ours) in ours
        s_ref = get(ref, k, -1)
        if s_ref == -1
            only_ours += 1
        elseif s_ref == s_ours
            n_match += 1
        else
            diff_support += 1
        end
    end

    only_ref = length(ref) - n_match - diff_support
    union_size = n_match + only_ours + only_ref + diff_support
    match_pct = union_size == 0 ? 100.0 : (100.0 * n_match / union_size)
    exact = (only_ours == 0 && only_ref == 0 && diff_support == 0)

    return CompareResult(:exact, length(ours), length(ref), n_match,
                         only_ours, only_ref, diff_support, match_pct, exact,
                         UInt64(0), UInt64(0))
end

function _count_nonempty_lines(path::AbstractString)
    c = 0
    open(path, "r") do io
        for line in eachline(io)
            s = strip(line)
            (isempty(s) || startswith(s, '@')) || (c += 1)
        end
    end
    return c
end

"""
    compare_files(ours_path, ref_path; max_exact = 5_000_000, force_fingerprint = false) -> CompareResult

So sánh hai file output chuẩn SPMF. Tự động dùng `fingerprint` nếu số dòng vượt `max_exact`
hoặc khi `force_fingerprint = true`.
"""
function compare_files(ours_path::AbstractString, ref_path::AbstractString;
                       max_exact::Int = 5_000_000, force_fingerprint::Bool = false)::CompareResult
    if force_fingerprint || _count_nonempty_lines(ours_path) > max_exact ||
       _count_nonempty_lines(ref_path) > max_exact
        n_ours, h_ours = fingerprint_file(ours_path)
        n_ref, h_ref = fingerprint_file(ref_path)
        exact = (n_ours == n_ref && h_ours == h_ref)
        return CompareResult(:fingerprint, n_ours, n_ref,
                             exact ? n_ours : -1, -1, -1, -1,
                             exact ? 100.0 : NaN, exact, h_ours, h_ref)
    end
    return compare_dicts(load_itemsets_file(ours_path), load_itemsets_file(ref_path))
end

function print_compare_report(r::CompareResult; io::IO = stdout)
    if r.mode == :exact
        println(io, "Chế độ so sánh : chi tiết (Dict)")
        println(io, "  Số tập nhóm  : ", r.n_ours)
        println(io, "  Số tập SPMF  : ", r.n_ref)
        println(io, "  Khớp hoàn toàn: ", r.n_match, " (", round(r.match_pct; digits = 4), "%)")
        println(io, "  Chỉ nhóm có  : ", r.only_ours)
        println(io, "  Chỉ SPMF có  : ", r.only_ref)
        println(io, "  Lệch support : ", r.diff_support)
    else
        println(io, "Chế độ so sánh : fingerprint (SHA-256 64-bit sum)")
        println(io, "  Số dòng nhóm : ", r.n_ours, " | hash = 0x", string(r.hash_ours; base = 16, pad = 16))
        println(io, "  Số dòng SPMF : ", r.n_ref, " | hash = 0x", string(r.hash_ref; base = 16, pad = 16))
        println(io, "  Kết luận     : ", r.exact_match ? "KHỚP 100%" : "LỆCH")
    end
end

function _compare_cli(args::Vector{String})
    force_fp = false
    files = String[]
    for arg in args
        if arg == "--fingerprint"
            force_fp = true
        else
            push!(files, arg)
        end
    end
    if length(files) != 2
        println(stderr, "Cách dùng: julia --project=. scripts/compare_spmf.jl [--fingerprint] <file_nhom> <file_spmf>")
        return 1
    end
    res = compare_files(files[1], files[2]; force_fingerprint = force_fp)
    print_compare_report(res)
    return res.exact_match ? 0 : 1
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(_compare_cli(ARGS))
end
