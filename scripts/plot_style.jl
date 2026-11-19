# Quy chuẩn hình dùng chung (KE_HOACH_DU_AN.md, mục 11.3): màu và kiểu đường CỐ ĐỊNH cho từng
# cài đặt, trục có đơn vị, chữ đủ lớn khi in một cột, xuất cả PDF (báo cáo) lẫn PNG (notebook, README).

# Máy không có màn hình (Colab, CI): cho GR vẽ thẳng ra file, không mở cửa sổ.
haskey(ENV, "GKSwstype") || (ENV["GKSwstype"] = "100")
using Plots, Statistics
gr()
default(fontfamily = "sans-serif", titlefontsize = 10, guidefontsize = 9, tickfontsize = 8,
        legendfontsize = 7, linewidth = 1.8, markersize = 4, framestyle = :box, grid = :y, gridalpha = 0.25,
        dpi = 200)

const STYLE = Dict(
    "nhom-v6" => (label = "Nhóm (v6, bản mặc định)", color = RGB(0.05, 0.25, 0.60), ls = :solid, shape = :circle),
    "nhom-v0" => (label = "Nhóm (v0, bản cơ bản)", color = RGB(0.45, 0.65, 0.90), ls = :dash, shape = :circle),
    "spmf-Eclat" => (label = "SPMF Eclat", color = RGB(0.90, 0.50, 0.05), ls = :solid, shape = :diamond),
    "spmf-Eclat_bitset" => (label = "SPMF Eclat_bitset", color = RGB(0.80, 0.10, 0.10), ls = :solid, shape = :utriangle),
    "spmf-Apriori" => (label = "SPMF Apriori", color = RGB(0.45, 0.45, 0.45), ls = :dot, shape = :square),
    "spmf-FPGrowth_itemsets" => (label = "SPMF FP-Growth", color = RGB(0.30, 0.30, 0.30), ls = :dashdot, shape = :star5),
)
style_key(impl, variant) = impl == "nhom" ? "nhom-$variant" : "spmf-$variant"

const FIGDIR = joinpath(results_dir(), "figures")

"""Lưu hình ở cả PDF và PNG với cùng tên (ví dụ F03_thoi_gian)."""
function save_figure(p, name)
    mkpath(FIGDIR)
    savefig(p, joinpath(FIGDIR, name * ".pdf"))
    savefig(p, joinpath(FIGDIR, name * ".png"))
    println("  đã lưu ", name, ".pdf/.png")
end

"""Đọc CSV đơn giản (không có dấu phẩy trong ô)."""
function read_rows(path)
    isfile(path) || return Dict{String,String}[]
    lines = collect(eachline(path))
    header = split(lines[1], ",")
    return [Dict{String,String}(zip(header, split(l, ","))) for l in lines[2:end] if !isempty(strip(l))]
end

numval(s) = (x = tryparse(Float64, s); x === nothing ? NaN : x)
minsup_value(s) = endswith(s, "%") ? parse(Float64, s[1:end-1]) : 100 * parse(Float64, s)
