# Vẽ các hình của Chương 2 và Ứng dụng 1 (phần của B) từ CSV trong results/.
#
#   julia --project=scripts scripts/plots.jl
#
# F03 thời gian theo minsup | F04 số tập theo minsup | F05 bộ nhớ đỉnh | F06 khả năng mở rộng
# F07 độ dài giao dịch | F09 so với Apriori, FP-Growth | F11 luật kết hợp của Ứng dụng 1
# (F08, F10 của A: scripts/plots_a.jl). Mọi hình chỉ vẽ từ CSV (quyết định D14).

include(joinpath(@__DIR__, "config.jl"))
include(joinpath(@__DIR__, "plot_style.jl"))

const RES = results_dir()

"""
Thời gian thuật toán dùng để so với SPMF: từ lúc bắt đầu đọc file input đến lúc ghi xong output, không gồm
khởi động tiến trình và biên dịch JIT. Thời gian SPMF tự in ra đã gồm cả bước đọc file, nên với cài đặt của
nhóm phải cộng thêm t_read_s (cách so sánh thận trọng, không làm lợi cho nhóm).
"""
algo_time(r) = numval(r["t_algo_s"]) + (r["impl"] == "nhom" ? numval(r["t_read_s"]) : 0.0)

safemedian(v) = isempty(v) ? NaN : median(v)     # không có lần chạy hợp lệ (ví dụ timeout): để trống trên hình
safemax(v) = isempty(v) ? NaN : maximum(v)

"""Trung vị thời gian thuật toán theo (bộ dữ liệu, minsup, cài đặt)."""
function medians(rows)
    groups = Dict{Tuple{String,String,String},Vector{Float64}}()
    counts = Dict{Tuple{String,String},Int}()
    for r in rows
        r["status"] == "ok" || continue
        key = (r["dataset"], r["minsup"], style_key(r["impl"], r["variant"]))
        push!(get!(groups, key, Float64[]), algo_time(r))
        n = tryparse(Int, r["n_itemsets"])
        n === nothing || (counts[(r["dataset"], r["minsup"])] = n)
    end
    return Dict(k => median(v) for (k, v) in groups), counts
end

"""Một khung cho mỗi bộ dữ liệu: thời gian (log) theo minsup giảm dần từ trái sang phải."""
function runtime_panels(rows, keys, grid; title_prefix = "")
    med, _ = medians(rows)
    panels = []
    for (ds, _, kind) in DATASETS
        haskey(grid, ds) || continue
        lv = grid[ds]
        p = plot(; title = "$ds ($kind)", xlabel = "minsup", ylabel = "thời gian (s)", yscale = :log10,
                 xticks = (1:length(lv), lv), xrotation = 30, legend = ds == "chess" ? :topleft : false)
        for key in keys
            ys = [get(med, (ds, ms, key), NaN) for ms in lv]
            all(isnan, ys) && continue
            s = STYLE[key]
            plot!(p, 1:length(lv), ys; label = s.label, color = s.color, ls = s.ls, marker = s.shape)
        end
        push!(panels, p)
    end
    while length(panels) % 3 != 0                    # lưới 2×3: thêm khung trống cho đủ ô
        push!(panels, plot(; framestyle = :none, grid = false, legend = false))
    end
    return panels
end

function fig_runtime(grid)
    rows = read_rows(joinpath(RES, "e2_runtime.csv"))
    isempty(rows) && return println("  bỏ qua F03/F04: chưa có e2_runtime.csv")
    panels = runtime_panels(rows, ["nhom-v6", "nhom-v0", "spmf-Eclat", "spmf-Eclat_bitset"], grid)
    save_figure(plot(panels...; layout = (2, 3), size = (1000, 560), margin = 3Plots.mm), "F03_thoi_gian_theo_minsup")

    _, counts = medians(rows)
    pd = plot(; title = "Dữ liệu dày", xlabel = "minsup (%)", ylabel = "số tập phổ biến", yscale = :log10, xflip = true)
    ps = plot(; title = "Dữ liệu thưa", xlabel = "minsup (%)", ylabel = "số tập phổ biến", yscale = :log10,
              xscale = :log10, xflip = true)
    for (ds, _, kind) in DATASETS
        haskey(grid, ds) || continue
        xs = [minsup_value(ms) for ms in grid[ds]]
        ys = [Float64(get(counts, (ds, ms), 0)) for ms in grid[ds]]
        plot!(kind == "dày" ? pd : ps, xs, max.(ys, 1); label = ds, marker = :circle)
    end
    save_figure(plot(pd, ps; layout = (1, 2), size = (900, 340), margin = 3Plots.mm), "F04_so_tap_theo_minsup")
end

function fig_memory()
    rows = read_rows(joinpath(RES, "e4_memory.csv"))
    isempty(rows) && return println("  bỏ qua F05: chưa có e4_memory.csv")
    dss = unique(r["dataset"] for r in rows)
    vars = ["v0", "v6"]
    # RAM nền đo ở tiến trình riêng nên phép trừ có thể ra số âm nhỏ: vẽ RAM đỉnh toàn tiến trình và kẻ
    # đường RAM nền (Julia đã nạp gói và khởi động) để thấy phần tăng thêm.
    rss = [safemedian([numval(r["maxrss_mb"]) for r in rows if r["dataset"] == ds && r["variant"] == v]) for ds in dss, v in vars]
    base = median([numval(r["baseline_mb"]) for r in rows])
    tid = [safemedian([numval(r["tidset_peak_mb"]) for r in rows if r["dataset"] == ds && r["variant"] == v]) for ds in dss, v in vars]
    labels = permutedims([STYLE["nhom-$v"].label for v in vars])
    colors = permutedims([STYLE["nhom-$v"].color for v in vars])
    x = 1:length(dss)
    p1 = bar([x .- 0.2 x .+ 0.2], rss; bar_width = 0.38, label = labels, color = colors, xticks = (x, dss),
             ylabel = "MiB", title = "RAM đỉnh của tiến trình", legend = :topright,
             ylims = (0, 1.15 * maximum(filter(!isnan, rss))))
    hline!(p1, [base]; color = :black, ls = :dash, label = "RAM nền của Julia ($(round(Int, base)) MiB)")
    lo = 10.0^floor(log10(minimum(filter(!isnan, tid))))      # cột trên trục log mọc từ đáy khung, không từ 1
    p2 = bar([x .- 0.2 x .+ 0.2], tid; bar_width = 0.38, label = false, color = colors, xticks = (x, dss),
             ylabel = "MiB", yscale = :log10, fillrange = lo, ylims = (lo, 3 * maximum(filter(!isnan, tid))),
             title = "Tidset đỉnh (bộ đếm nội bộ)")
    save_figure(plot(p1, p2; layout = (1, 2), size = (900, 330), margin = 3Plots.mm), "F05_bo_nho")
end

"""Hồi quy tuyến tính y = a·x + b, trả về (a, b, R²)."""
function linfit(x, y)
    X = [x ones(length(x))]
    a, b = X \ y
    ŷ = a .* x .+ b
    r2 = 1 - sum(abs2, y - ŷ) / sum(abs2, y .- mean(y))
    return a, b, r2
end

function fig_scalability()
    rows = read_rows(joinpath(RES, "e5_scalability.csv"))
    isempty(rows) && return println("  bỏ qua F06: chưa có e5_scalability.csv")
    pcts = [10, 25, 50, 75, 100]
    bases = unique(String(first(rsplit(r["dataset"], "_"; limit = 2))) for r in rows)
    panels = []
    for base in bases                       # mỗi bộ dữ liệu gốc một khung (Retail, Accidents)
        sel = [r for r in rows if startswith(r["dataset"], base * "_")]
        ms = sel[1]["minsup"]
        p = plot(; xlabel = "số giao dịch (% của $base)", ylabel = "thời gian (s)", legend = :topleft,
                 title = "$base, minsup $ms")
        for key in unique(style_key(r["impl"], r["variant"]) for r in sel)
            ys = [safemedian([algo_time(r) for r in sel if r["dataset"] == "$(base)_$pc" &&
                              style_key(r["impl"], r["variant"]) == key && r["status"] == "ok"]) for pc in pcts]
            any(isnan, ys) && continue
            a, b, r2 = linfit(Float64.(pcts), ys)
            s = STYLE[key]
            scatter!(p, pcts, ys; label = "$(s.label), R² = $(round(r2; digits = 3))", color = s.color, marker = s.shape)
            plot!(p, pcts, a .* pcts .+ b; label = false, color = s.color, ls = :dot)
        end
        push!(panels, p)
    end
    save_figure(plot(panels...; layout = (1, length(panels)), size = (500 * length(panels), 360), margin = 3Plots.mm),
                "F06_kha_nang_mo_rong")
end

function fig_length()
    rows = read_rows(joinpath(RES, "e6_length.csv"))
    isempty(rows) && return println("  bỏ qua F07: chưa có e6_length.csv")
    dss = sort(unique(r["dataset"] for r in rows))
    T = [parse(Int, replace(ds, "synth_T" => "")) for ds in dss]
    p1 = plot(; xlabel = "độ dài giao dịch trung bình T", ylabel = "thời gian (s)", yscale = :log10,
              legend = :topleft, title = "Thời gian")
    for key in ["nhom-v6", "spmf-Eclat"]
        ys = [safemedian([algo_time(r) for r in rows if r["dataset"] == ds && style_key(r["impl"], r["variant"]) == key &&
                          r["status"] == "ok"]) for ds in dss]
        s = STYLE[key]
        plot!(p1, T, ys; label = s.label, color = s.color, marker = s.shape, ls = s.ls)
    end
    nfi = [safemax([numval(r["n_itemsets"]) for r in rows if r["dataset"] == ds && r["impl"] == "nhom" && r["status"] == "ok"])
           for ds in dss]
    p2 = plot(T, nfi; xlabel = "độ dài giao dịch trung bình T", ylabel = "số tập phổ biến", yscale = :log10,
              marker = :circle, label = false, title = "Số tập phổ biến", color = :black)
    save_figure(plot(p1, p2; layout = (1, 2), size = (900, 330), margin = 3Plots.mm), "F07_do_dai_giao_dich")
end

function fig_algorithms(grid)
    rows = vcat(read_rows(joinpath(RES, "e9_algorithms.csv")), read_rows(joinpath(RES, "e2_runtime.csv")))
    isempty(read_rows(joinpath(RES, "e9_algorithms.csv"))) && return println("  bỏ qua F09: chưa có e9_algorithms.csv")
    panels = runtime_panels(rows, ["nhom-v6", "spmf-Eclat", "spmf-FPGrowth_itemsets", "spmf-Apriori"], grid)
    save_figure(plot(panels...; layout = (2, 3), size = (1000, 560), margin = 3Plots.mm), "F09_so_voi_apriori_fpgrowth")
end

function fig_rules()
    rows = read_rows(rootpath("results", "apps", "groceries", "rules.csv"))
    isempty(rows) && return println("  bỏ qua F11: chưa có results/apps/groceries/rules.csv")
    sup = [100numval(r["support"]) for r in rows]
    conf = [numval(r["confidence"]) for r in rows]
    lift = [numval(r["lift"]) for r in rows]
    p = scatter(sup, conf; zcolor = lift, color = :viridis, markersize = 4, markerstrokewidth = 0, label = false,
                xlabel = "support (%)", ylabel = "confidence", colorbar_title = "lift",
                title = "Groceries: $(length(rows)) luật (màu theo lift)")
    save_figure(plot(p; size = (560, 380)), "F11_luat_groceries")
end

function main()
    grid = load_grid()
    fig_runtime(grid)
    fig_memory()
    fig_scalability()
    fig_length()
    fig_algorithms(grid)
    fig_rules()
end

main()
