# Vẽ các hình phần của A từ CSV trong results/ (xuất cả PDF cho báo cáo lẫn PNG cho notebook/README):
#   F08  tỉ số thời gian vector (v3) / bitset (v4) theo mật độ tidset   ← results/e7_density.csv (E7, giả thuyết H2)
#   F10  bộ nhớ tidset đang sống theo tiến trình duyệt                  ← results/e10_memory_trace.csv (E10, giả thuyết H7)
#
#   julia --project=apps scripts/plots_a.jl
#
# Chạy bằng môi trường apps/ (đã có Plots.jl, cùng môi trường với Ứng dụng 2). Script chỉ đọc CSV,
# không chạy thuật toán, nên không cần gói EclatFIM.

include(joinpath(@__DIR__, "config_a.jl"))    # results_dir, load_grid, median_minsup

haskey(ENV, "GKSwstype") || (ENV["GKSwstype"] = "100")   # máy không có màn hình (Colab, CI): GR vẽ thẳng ra file
using Plots   # thư viện vẽ hình (chỉ dùng để vẽ, không dùng cho thuật toán)
gr()   # chọn bộ vẽ GR
default(fontfamily = "sans-serif", titlefontsize = 10, guidefontsize = 9, tickfontsize = 8,   # kiểu chữ, cỡ chữ mặc định
        legendfontsize = 7, linewidth = 1.8, markersize = 4, framestyle = :box, grid = :y, gridalpha = 0.25,   # (tiếp)
        dpi = 200)                            # cỡ chữ, khung, lưới: cùng phong cách với hình của B

const FIGDIR = joinpath(results_dir(), "figures")   # thư mục lưu hình

"""Lưu hình ở cả PDF (báo cáo) và PNG (notebook) với cùng tên."""
function save_figure(p, name)   # lưu PDF (báo cáo) và PNG (notebook)
    mkpath(FIGDIR)   # tạo thư mục nếu chưa có
    savefig(p, joinpath(FIGDIR, name * ".pdf"))   # bản vector cho LaTeX
    savefig(p, joinpath(FIGDIR, name * ".png"))   # bản ảnh cho notebook
    println("  saved ", name, ".pdf/.png")   # báo đã lưu
end

"""Đọc CSV đơn giản (không có dấu phẩy trong ô) thành vector các Dict cột → giá trị."""
function read_rows(path)   # đọc CSV thành vector các Dict
    isfile(path) || return Dict{String,String}[]   # chưa có file thì trả rỗng
    lines = collect(eachline(path))   # mọi dòng
    header = split(lines[1], ",")   # tên cột
    return [Dict{String,String}(zip(header, split(l, ","))) for l in lines[2:end] if !isempty(strip(l))]   # mỗi dòng → Dict
end

"""Chuỗi → số thực; ô trống hoặc không phải số → NaN (Plots bỏ qua điểm NaN)."""
numval(s) = (x = tryparse(Float64, s); x === nothing ? NaN : x)   # chuỗi → số; lỗi → NaN (Plots bỏ qua)

"""F08: điểm cân bằng giữa tidset dạng danh sách (v3) và dạng bit (v4) theo mật độ ρ."""
function fig_density()   # hình F08 từ E7
    rows = read_rows(joinpath(results_dir(), "e7_density.csv"))   # dữ liệu E7
    isempty(rows) && return println("  skip F08: results/e7_density.csv not found")   # chưa chạy E7 thì bỏ qua
    p = plot(; xscale = :log10, yscale = :log10, xlabel = "tidset density ρ = mean support / N (log)",   # hai trục thang log
             ylabel = "time ratio vector (v3) / bitset (v4)", legend = :topleft,   # trục y: tỉ số thời gian
             title = "When does a bitset beat a tid list?")   # tiêu đề
    hline!(p, [1.0]; color = :black, ls = :dot, label = "break-even (ratio = 1)")       # trên đường này: bitset nhanh hơn
    vline!(p, [1 / 32]; color = :gray, ls = :dash, label = "ρ = 1/32 (equal memory)")   # điểm cân bằng bộ nhớ lý thuyết
    syn = [r for r in rows if r["source"] == "synthetic"]                               # dữ liệu tổng hợp: đường liền
    plot!(p, [numval(r["density"]) for r in syn], [numval(r["t_v3"]) / numval(r["t_v4"]) for r in syn];   # đường dữ liệu tổng hợp
          label = "synthetic (controlled density)", color = :black, marker = :circle, markersize = 3)   # (tiếp)
    shapes = Dict("benchmark" => :diamond, "application1" => :square, "application2" => :utriangle)   # ký hiệu điểm theo nguồn
    names = Dict("benchmark" => "benchmark datasets", "application1" => "Groceries (Application 1)",   # nhãn chú giải theo nguồn
                 "application2" => "images (Application 2)")   # (tiếp)
    for src in ("benchmark", "application1", "application2")                           # dữ liệu thật: các điểm rời
        sel = [r for r in rows if r["source"] == src]   # các điểm của nguồn này
        isempty(sel) && continue   # nguồn không có điểm thì bỏ qua
        scatter!(p, [numval(r["density"]) for r in sel], [numval(r["t_v3"]) / numval(r["t_v4"]) for r in sel];   # vẽ các điểm rời
                 label = names[src], marker = shapes[src], markersize = 5)   # (tiếp)
    end
    grid = load_grid()   # để biết mức minsup giữa
    for r in rows                                                                       # ghi tên bộ ở mức minsup giữa
        r["source"] == "benchmark" && haskey(grid, r["dataset"]) && r["minsup"] == median_minsup(grid[r["dataset"]]) || continue   # chỉ ghi tên ở điểm minsup giữa
        annotate!(p, numval(r["density"]), numval(r["t_v3"]) / numval(r["t_v4"]), text("  " * r["dataset"], 6, :left))   # ghi tên bộ cạnh điểm
    end
    save_figure(plot(p; size = (560, 400)), "F08_density_bitset_vs_vector")   # lưu F08
end

"""F10: số byte tidset đang sống sau mỗi tập phổ biến được xuất, bản danh sách (v3) và bản bit (v4)."""
function fig_memory_trace()   # hình F10 từ E10
    rows = read_rows(joinpath(results_dir(), "e10_memory_trace.csv"))   # dữ liệu E10
    isempty(rows) && return println("  skip F10: results/e10_memory_trace.csv not found")   # chưa chạy E10 thì bỏ qua
    panels = []   # mỗi bộ một ô hình
    for ds in unique(r["dataset"] for r in rows)                                       # mỗi bộ dữ liệu một ô hình
        ms = first(r["minsup"] for r in rows if r["dataset"] == ds)   # minsup đã dùng
        p = plot(; xlabel = "index of emitted frequent itemset", ylabel = "live tidset memory (MiB)",   # trục x: thứ tự tập; trục y: MiB
                 title = "$ds, minsup $ms", legend = :topright)   # tiêu đề ô
        for (v, lab) in (("v3", "tid lists (v3)"), ("v4", "bitsets (v4)"))   # hai đường: danh sách và dãy bit
            sel = [r for r in rows if r["dataset"] == ds && r["variant"] == v]   # các điểm của phiên bản này
            plot!(p, [numval(r["itemset_index"]) for r in sel], [numval(r["bytes_current"]) / 2^20 for r in sel];   # byte → MiB
                  label = lab, linewidth = 1.2)   # (tiếp)
        end
        push!(panels, p)   # thêm ô
    end
    save_figure(plot(panels...; layout = (1, length(panels)), size = (520 * length(panels), 340), margin = 3Plots.mm),   # ghép các ô theo hàng ngang
                "F10_memory_trace")   # lưu F10
end

fig_density()   # vẽ F08
fig_memory_trace()   # vẽ F10
