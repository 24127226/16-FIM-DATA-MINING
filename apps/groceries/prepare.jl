# Ứng dụng 1, bước 1: chuyển Groceries (CSV, tên mặt hàng) sang định dạng SPMF.
#
#   julia --project=. apps/groceries/prepare.jl
#
# Quyết định biến đổi (R17, KE_HOACH_DU_AN.md mục 9.1 và 9.2):
#   - mỗi hóa đơn (một dòng CSV) là MỘT giao dịch; mỗi mặt hàng là một item;
#   - mã item gán theo thứ tự chữ cái của tên (1..169), tên lưu trong dòng `@ITEM=mã=tên`
#     đúng cú pháp SPMF; bộ đọc của nhóm bỏ qua dòng `@` khi khai thác;
#   - bỏ mặt hàng trùng trong cùng hóa đơn; ghi đúng một dấu cách giữa các mã (SPMF yêu cầu).
# Ngoài bản chính, script ghi thêm một phương án so sánh: bỏ các hóa đơn chỉ có 1 mặt hàng
# (không thể tạo luật, nhưng làm thay đổi N và support), rồi in thống kê của cả hai phương án.

include(joinpath(@__DIR__, "..", "..", "scripts", "common.jl"))

function read_baskets(path)
    baskets = Vector{Vector{String}}()
    for line in eachline(path)
        s = strip(line)
        isempty(s) && continue
        push!(baskets, unique!(String[strip(x) for x in split(s, ',') if !isempty(strip(x))]))
    end
    return baskets
end

function write_spmf_named(path, baskets, names, index)
    open(path, "w") do io
        println(io, "@CONVERTED_FROM_TEXT")
        for (k, name) in enumerate(names)
            println(io, "@ITEM=", k, "=", name)
        end
        for b in baskets
            println(io, join(sort!([index[x] for x in b]), ' '))
        end
    end
end

function describe(io, label, baskets, m)
    N = length(baskets)
    lens = length.(baskets)
    L = sum(lens) / N
    println(io, "| ", label, " | ", N, " | ", m, " | ", round(L; digits = 2), " | ",
            round(100 * L / m; digits = 2), "% | ", count(==(1), lens), " |")
end

function main()
    src = rootpath("data", "apps", "groceries", "groceries.csv")
    isfile(src) || error("Chưa có $src: chạy julia --project=. scripts/fetch_data.jl groceries")
    baskets = read_baskets(src)
    names = sort!(unique(reduce(vcat, baskets)))            # thứ tự chữ cái → mã 1..m
    index = Dict(name => k for (k, name) in enumerate(names))
    m = length(names)

    out_main = rootpath("data", "apps", "groceries", "groceries.txt")
    out_multi = rootpath("data", "apps", "groceries", "groceries_multi.txt")
    multi = [b for b in baskets if length(b) >= 2]
    write_spmf_named(out_main, baskets, names, index)
    write_spmf_named(out_multi, multi, names, index)

    io = IOBuffer()
    println(io, "# Ứng dụng 1: các phương án biến đổi dữ liệu Groceries\n")
    println(io, "Sinh bởi `apps/groceries/prepare.jl`.\n")
    println(io, "| Phương án | N | m | L̄ | Mật độ L̄/m | Số hóa đơn 1 món |")
    println(io, "|---|---|---|---|---|---|")
    describe(io, "Mỗi hóa đơn là một giao dịch (chọn)", baskets, m)
    describe(io, "Bỏ hóa đơn chỉ có 1 món", multi, m)
    println(io)
    freq = Dict{String,Int}()
    for b in baskets, x in b
        freq[x] = get(freq, x, 0) + 1
    end
    top = sort!(collect(freq); by = p -> (-p[2], p[1]))[1:10]
    println(io, "## 10 mặt hàng phổ biến nhất\n")
    println(io, "| Mặt hàng | Số hóa đơn | Support |")
    println(io, "|---|---|---|")
    for (name, c) in top
        println(io, "| ", name, " | ", c, " | ", round(100c / length(baskets); digits = 2), "% |")
    end
    mkpath(rootpath("results", "apps", "groceries"))
    report = rootpath("results", "apps", "groceries", "B08_bien_doi.md")
    write(report, String(take!(io)))
    println(read(report, String))
    println("Đã ghi ", out_main, " và ", out_multi)
end

main()
