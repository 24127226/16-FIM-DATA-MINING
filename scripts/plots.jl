# Kịch bản sinh biểu đồ báo cáo (PDF vector) và ảnh minh họa (PNG 300 dpi) trực tiếp từ tệp CSV.
#
# Cú pháp thực thi:
#   julia --project=scripts scripts/plots.jl             # sinh toàn bộ biểu đồ có sẵn CSV
#   julia --project=scripts scripts/plots.jl f11         # sinh riêng biểu đồ F11 (Groceries)
#   julia --project=scripts scripts/plots.jl f03 f04     # sinh các biểu đồ chỉ định

ENV["GKSwstype"] = "100"   # chạy headless không cần cửa sổ đồ họa (Colab/Linux/Windows)

using CSV
using DataFrames
using Plots
using Statistics

const REPO_ROOT   = normpath(joinpath(@__DIR__, ".."))
const RESULTS_DIR = joinpath(REPO_ROOT, "results")
const FIGURES_DIR = joinpath(RESULTS_DIR, "figures")

# Bảng màu và kiểu đường cố định theo KE_HOACH_DU_AN.md mục 11.3
const STYLE_MAP = Dict{Tuple{String,String},NamedTuple{(:label,:color,:ls,:marker),Tuple{String,Symbol,Symbol,Symbol}}}(
    ("julia", "best")              => (label = "EclatFIM (v6)",     color = :navy,       ls = :solid,   marker = :circle),
    ("julia", "v6")                => (label = "EclatFIM (v6)",     color = :navy,       ls = :solid,   marker = :circle),
    ("julia", "v0")                => (label = "EclatFIM (v0)",     color = :deepskyblue,ls = :dash,    marker = :square),
    ("julia", "v1")                => (label = "EclatFIM (v1)",     color = :steelblue,  ls = :solid,   marker = :circle),
    ("spmf",  "Eclat")             => (label = "SPMF Eclat",        color = :darkorange, ls = :solid,   marker = :diamond),
    ("spmf",  "Eclat_bitset")      => (label = "SPMF Eclat_bitset", color = :crimson,    ls = :solid,   marker = :utriangle),
    ("spmf",  "Apriori")           => (label = "SPMF Apriori",      color = :gray45,     ls = :dashdot, marker = :xcross),
    ("spmf",  "FPGrowth_itemsets") => (label = "SPMF FP-Growth",    color = :gray25,     ls = :dot,     marker = :star5),
)

default(
    fontfamily = "sans-serif",
    guidefontsize = 9,
    tickfontsize = 8,
    legendfontsize = 8,
    titlefontsize = 10,
    linewidth = 2.0,
    markersize = 4.5,
    dpi = 300,
    gridalpha = 0.25,
)

"""Chuyển chuỗi minsup (`"40%"` hoặc `"0.4"`) sang giá trị phần trăm (40.0) để vẽ trục hoành."""
function minsup_to_pct(x)::Float64
    s = strip(string(x))
    return endswith(s, '%') ? parse(Float64, s[1:end-1]) : 100.0 * parse(Float64, s)
end

"""Lưu hình sang cả PDF vector (cho báo cáo LaTeX) và PNG (cho notebook/README)."""
function save_figure(plt, stem::AbstractString)
    mkpath(FIGURES_DIR)
    pdf_path = joinpath(FIGURES_DIR, stem * ".pdf")
    png_path = joinpath(FIGURES_DIR, stem * ".png")
    savefig(plt, pdf_path)
    savefig(plt, png_path)
    println("  ✓ Đã xuất ", basename(pdf_path), " & ", basename(png_path))
end

"""Lấy trung vị theo nhóm cho dữ liệu benchmark (bỏ qua dòng timeout/missing)."""
function aggregate_medians(df::DataFrame, group_cols::Vector{Symbol}, val_col::Symbol)
    clean = filter(row -> !ismissing(row[val_col]) && string(row[val_col]) != "timeout", df)
    clean = transform(clean, val_col => ByRow(x -> x isa Number ? Float64(x) : parse(Float64, string(x))) => :_val)
    return combine(groupby(clean, group_cols),
                   :_val => median => :med,
                   :_val => minimum => :lo,
                   :_val => maximum => :hi)
end

# ---------------------------------------------------------------------------
# F11: Ứng dụng 1 (Groceries) — phân tán support–confidence, tô màu theo lift
# ---------------------------------------------------------------------------

function plot_f11_groceries(; csv_path = joinpath(RESULTS_DIR, "groceries_rules.csv"))
    if !isfile(csv_path)
        @info "Bỏ qua F11: chưa có $csv_path"
        return false
    end
    df = CSV.read(csv_path, DataFrame)
    sup_pct = 100.0 .* Float64.(df.support)
    conf_pct = 100.0 .* Float64.(df.confidence)
    lifts = Float64.(df.lift)

    plt = scatter(
        sup_pct, conf_pct;
        zcolor = lifts,
        color = :viridis,
        colorbar_title = "\nLift",
        xlabel = "Support (%)",
        ylabel = "Confidence (%)",
        title = "Groceries: 125 Association Rules (minsup = 1%, minconf = 0.3)",
        label = "",
        markersize = 5.5,
        markerstrokewidth = 0.4,
        markerstrokecolor = :black,
        alpha = 0.88,
        size = (680, 440),
        margin = 5Plots.mm,
    )

    # Đánh dấu top-3 luật có lift cao nhất
    top_idx = partialsortperm(lifts, 1:min(3, length(lifts)); rev = true)
    scatter!(plt, sup_pct[top_idx], conf_pct[top_idx];
             color = :red, markershape = :star5, markersize = 8,
             markerstrokecolor = :black, label = "Top-3 Rules by Lift")

    save_figure(plt, "F11_groceries_rules")
    return true
end

# ---------------------------------------------------------------------------
# F03: E2 — Thời gian theo minsup (trục y log, minsup giảm dần từ trái sang phải)
# ---------------------------------------------------------------------------

function plot_f03_time_vs_minsup(; csv_path = joinpath(RESULTS_DIR, "e2_time.csv"), best_variant = "v6")
    if !isfile(csv_path)
        @info "Bỏ qua F03: chưa có $csv_path"
        return false
    end
    df = CSV.read(csv_path, DataFrame)
    df.minsup_pct = minsup_to_pct.(df.minsup)
    agg = aggregate_medians(df, [:dataset, :minsup_pct, :impl, :variant], :t_algo_s)

    datasets = unique(agg.dataset)
    subplots = Plots.Plot[]
    for ds in datasets
        sub = filter(r -> r.dataset == ds, agg)
        p = plot(title = string(ds), xlabel = "minsup (%)", ylabel = "Algorithm Time (s)",
                 yscale = :log10, xflip = true, legend = :topleft)
        for g in groupby(sub, [:impl, :variant])
            impl = string(first(g.impl))
            var  = string(first(g.variant))
            key  = (impl == "julia" && var == best_variant && var != "v0") ? ("julia", "best") : (impl, var)
            st   = get(STYLE_MAP, key, (label = "$impl-$var", color = :black, ls = :solid, marker = :circle))
            ord  = sortperm(g.minsup_pct; rev = true)
            ys   = max.(g.med[ord], 1e-5)
            plot!(p, g.minsup_pct[ord], ys; label = st.label, color = st.color,
                  linestyle = st.ls, marker = st.marker)
        end
        push!(subplots, p)
    end

    nrows = cld(length(subplots), 2)
    plt = plot(subplots...; layout = (nrows, min(2, length(subplots))),
               size = (920, 340 * nrows), margin = 4Plots.mm)
    save_figure(plt, "F03_time_vs_minsup")
    return true
end

# ---------------------------------------------------------------------------
# F04: E3 — Frequent Itemsets vs minsup (dense vs sparse, log y-axis)
# ---------------------------------------------------------------------------

function plot_f04_itemsets_vs_minsup(; csv_path = joinpath(RESULTS_DIR, "e2_time.csv"))
    if !isfile(csv_path)
        @info "Bỏ qua F04: chưa có $csv_path"
        return false
    end
    df = CSV.read(csv_path, DataFrame)
    df.minsup_pct = minsup_to_pct.(df.minsup)
    agg = combine(groupby(df, [:dataset, :minsup_pct]), :n_itemsets => first => :n_itemsets)

    dense_names  = Set(["chess", "mushroom", "accidents"])
    p_dense  = plot(title = "Dense Datasets", xlabel = "minsup (%)", ylabel = "Frequent Itemsets",
                    yscale = :log10, xflip = true, legend = :topleft)
    p_sparse = plot(title = "Sparse Datasets", xlabel = "minsup (%)", ylabel = "Frequent Itemsets",
                    yscale = :log10, xflip = true, legend = :topleft)

    for g in groupby(agg, :dataset)
        ds  = string(first(g.dataset))
        ord = sortperm(g.minsup_pct; rev = true)
        ys  = max.(Float64.(g.n_itemsets[ord]), 1.0)
        target = lowercase(ds) in dense_names ? p_dense : p_sparse
        plot!(target, g.minsup_pct[ord], ys; label = ds, marker = :circle)
    end

    plt = plot(p_dense, p_sparse; layout = (1, 2), size = (920, 360), margin = 4Plots.mm)
    save_figure(plt, "F04_itemsets_vs_minsup")
    return true
end

# ---------------------------------------------------------------------------
# F05: E4 — Peak Memory at Median minsup (v0 vs v6: tidset peak KiB & process delta RSS)
# ---------------------------------------------------------------------------

function plot_f05_memory(; csv_path = joinpath(RESULTS_DIR, "e4_memory.csv"))
    if !isfile(csv_path)
        @info "Bỏ qua F05: chưa có $csv_path"
        return false
    end
    df = CSV.read(csv_path, DataFrame)
    jdf = filter(r -> string(r.impl) == "julia", df)
    datasets = unique(string.(jdf.dataset))
    x = 1:length(datasets)
    w = 0.34

    tid_v0 = [Float64(first(filter(r -> string(r.dataset) == d && string(r.variant) == "v0", jdf).tidset_peak_bytes)) / 1024.0 for d in datasets]
    tid_v6 = [Float64(first(filter(r -> string(r.dataset) == d && string(r.variant) == "v6", jdf).tidset_peak_bytes)) / 1024.0 for d in datasets]

    rss_v0 = [max(0.1, Float64(first(filter(r -> string(r.dataset) == d && string(r.variant) == "v0", jdf).delta_rss_mb))) for d in datasets]
    rss_v6 = [max(0.1, Float64(first(filter(r -> string(r.dataset) == d && string(r.variant) == "v6", jdf).delta_rss_mb))) for d in datasets]

    p1 = bar(x .- w/2, tid_v0; bar_width = w, label = "EclatFIM (v0)", color = :deepskyblue,
             xticks = (x, datasets), ylabel = "Peak Live Tidset (KiB)", title = "Peak Tidset Memory (EclatStats)",
             yscale = :log10, legend = :topright)
    bar!(p1, x .+ w/2, tid_v6; bar_width = w, label = "EclatFIM (v6)", color = :navy)

    p2 = bar(x .- w/2, rss_v0; bar_width = w, label = "EclatFIM (v0)", color = :deepskyblue,
             xticks = (x, datasets), ylabel = "Process Delta RSS (MiB)", title = "Added Process Memory (RSS - Baseline)",
             legend = :topright)
    bar!(p2, x .+ w/2, rss_v6; bar_width = w, label = "EclatFIM (v6)", color = :navy)

    plt = plot(p1, p2; layout = (1, 2), size = (920, 360), margin = 4Plots.mm)
    save_figure(plt, "F05_peak_memory")
    return true
end

# ---------------------------------------------------------------------------
# F06: E5 — Scalability (linear regression & R²)
# ---------------------------------------------------------------------------

function plot_f06_scalability(; csv_path = joinpath(RESULTS_DIR, "e5_scalability.csv"))
    if !isfile(csv_path)
        @info "Bỏ qua F06: chưa có $csv_path"
        return false
    end
    df = CSV.read(csv_path, DataFrame)
    agg = aggregate_medians(df, [:n_tx, :impl, :variant], :t_algo_s)

    plt = plot(xlabel = "Number of Transactions (N)", ylabel = "Algorithm Time (s)",
               title = "Scalability on Retail Subsets (minsup = 0.2%)", legend = :topleft,
               size = (680, 420), margin = 5Plots.mm)

    for g in groupby(agg, [:impl, :variant])
        impl = string(first(g.impl))
        var  = string(first(g.variant))
        st   = get(STYLE_MAP, (impl, var), (label = "$impl-$var", color = :black, ls = :solid, marker = :circle))
        ord = sortperm(g.n_tx)
        xs = Float64.(g.n_tx[ord])
        ys = Float64.(g.med[ord])
        x̄, ȳ = mean(xs), mean(ys)
        a = sum((xs .- x̄) .* (ys .- ȳ)) / max(sum((xs .- x̄).^2), 1e-12)
        b = ȳ - a * x̄
        ŷ = a .* xs .+ b
        ss_res = sum((ys .- ŷ).^2)
        ss_tot = max(sum((ys .- ȳ).^2), 1e-12)
        r2 = 1.0 - ss_res / ss_tot

        lbl = "$(st.label) (R² = $(round(r2; digits=4)))"
        scatter!(plt, xs, ys; label = lbl, color = st.color, marker = st.marker)
        plot!(plt, xs, ŷ; label = "", color = st.color, linestyle = :dash)
    end

    save_figure(plt, "F06_scalability")
    return true
end

# ---------------------------------------------------------------------------
# F07: E6 — Effect of Average Transaction Length L̄
# ---------------------------------------------------------------------------

function plot_f07_tx_length(; csv_path = joinpath(RESULTS_DIR, "e6_tx_length.csv"))
    if !isfile(csv_path)
        @info "Bỏ qua F07: chưa có $csv_path"
        return false
    end
    df = CSV.read(csv_path, DataFrame)
    agg = aggregate_medians(df, [:avg_len, :impl, :variant], :t_algo_s)

    plt = plot(xlabel = "Target Average Transaction Length (L̄)", ylabel = "Algorithm Time (s)",
               title = "Impact of Transaction Length (Synthetic, N = 50,000, minsup = 1%)",
               yscale = :log10, legend = :topleft, size = (680, 420), margin = 5Plots.mm)

    for g in groupby(agg, [:impl, :variant])
        impl = string(first(g.impl))
        var  = string(first(g.variant))
        st   = get(STYLE_MAP, (impl, var), (label = "$impl-$var", color = :black, ls = :solid, marker = :circle))
        ord = sortperm(g.avg_len)
        plot!(plt, g.avg_len[ord], max.(g.med[ord], 1e-5);
              label = st.label, color = st.color, linestyle = st.ls, marker = st.marker)
    end

    save_figure(plt, "F07_tx_length")
    return true
end

# ---------------------------------------------------------------------------
# F09: E9 — EclatFIM (v6) vs SPMF Apriori and FP-Growth (H6)
# ---------------------------------------------------------------------------

function plot_f09_vs_apriori_fp(; csv_path = joinpath(RESULTS_DIR, "e9_vs_apriori_fp.csv"))
    if !isfile(csv_path)
        @info "Bỏ qua F09: chưa có $csv_path"
        return false
    end
    df = CSV.read(csv_path, DataFrame)
    df.minsup_pct = minsup_to_pct.(df.minsup)
    agg = aggregate_medians(df, [:dataset, :minsup_pct, :impl, :variant], :t_algo_s)

    datasets = unique(agg.dataset)
    subplots = Plots.Plot[]
    for ds in datasets
        sub = filter(r -> r.dataset == ds, agg)
        p = plot(title = string(ds), xlabel = "minsup (%)", ylabel = "Algorithm Time (s)",
                 yscale = :log10, xflip = true, legend = :topleft)
        for g in groupby(sub, [:impl, :variant])
            impl = string(first(g.impl))
            var  = string(first(g.variant))
            st   = get(STYLE_MAP, (impl, var), (label = "$impl-$var", color = :black, ls = :solid, marker = :circle))
            ord  = sortperm(g.minsup_pct; rev = true)
            ys   = max.(g.med[ord], 1e-5)
            plot!(p, g.minsup_pct[ord], ys; label = st.label, color = st.color,
                  linestyle = st.ls, marker = st.marker)
        end
        push!(subplots, p)
    end

    nrows = cld(length(subplots), 2)
    plt = plot(subplots...; layout = (nrows, min(2, length(subplots))),
               size = (920, 340 * nrows), margin = 4Plots.mm)
    save_figure(plt, "F09_vs_apriori_fp")
    return true
end

# ---------------------------------------------------------------------------
# F02: Sơ đồ kiến trúc phần mềm và luồng dữ liệu (mục III.C)
# ---------------------------------------------------------------------------

function _draw_box!(plt, x, y, w, h, title_str, sub_str; fill = :aliceblue, border = :navy)
    xs = [x - w/2, x + w/2, x + w/2, x - w/2, x - w/2]
    ys = [y - h/2, y - h/2, y + h/2, y + h/2, y - h/2]
    plot!(plt, xs, ys; seriestype = :shape, fillcolor = fill, linecolor = border,
          linewidth = 1.6, label = "")
    annotate!(plt, x, y + h * 0.16, text(title_str, 9, "sans-serif", :black, :center))
    annotate!(plt, x, y - h * 0.20, text(sub_str, 7, "sans-serif", :gray25, :center))
end

function _draw_arrow!(plt, x1, y1, x2, y2)
    plot!(plt, [x1, x2], [y1, y2]; arrow = true, color = :gray20, linewidth = 1.5, label = "")
end

function plot_f02_architecture()
    plt = plot(; xlims = (0, 10), ylims = (0, 6.2), framestyle = :none,
               legend = false, size = (760, 420), margin = 2Plots.mm)

    # Row 1: Primary pipeline (left -> right)
    _draw_box!(plt, 1.4, 4.7, 2.2, 1.3, "SPMF Datasets", "benchmark / toy / apps";
               fill = :whitesmoke, border = :gray40)
    _draw_box!(plt, 4.9, 4.7, 2.7, 1.3, "src/utils.jl (I/O)", "read_spmf, minsup_count";
               fill = :lightcyan, border = :teal)
    _draw_box!(plt, 8.4, 4.7, 2.4, 1.3, "Interface Contract", "TransactionDB, EclatConfig";
               fill = :cornsilk, border = :darkorange)

    # Row 2: Core algorithm & consumers
    _draw_box!(plt, 8.4, 2.5, 2.4, 1.3, "src/algorithm/", "eclat!, tidsets (v0..v6)";
               fill = :lavender, border = :navy)
    _draw_box!(plt, 4.9, 2.5, 2.7, 1.3, "Streaming sink", "write_itemset / Dict / Stats";
               fill = :lightcyan, border = :teal)
    _draw_box!(plt, 1.4, 2.5, 2.2, 1.3, "CLI & Rules", "demo.jl, src/rules.jl";
               fill = :honeydew, border = :forestgreen)

    # Row 3: Verification, Benchmarking & Applications
    _draw_box!(plt, 2.0, 0.75, 3.1, 1.0, "Verification & CI", "test/ (200-DB oracle, SPMF)";
               fill = :mistyrose, border = :crimson)
    _draw_box!(plt, 5.5, 0.75, 2.9, 1.0, "Benchmarking", "scripts/bench.jl -> CSV -> plots.jl";
               fill = :aliceblue, border = :steelblue)
    _draw_box!(plt, 8.6, 0.75, 2.3, 1.0, "Applications", "Groceries & BoVW";
               fill = :honeydew, border = :forestgreen)

    # Data flow arrows
    _draw_arrow!(plt, 2.5, 4.7, 3.55, 4.7)
    _draw_arrow!(plt, 6.25, 4.7, 7.2, 4.7)
    _draw_arrow!(plt, 8.4, 4.05, 8.4, 3.15)
    _draw_arrow!(plt, 7.2, 2.5, 6.25, 2.5)
    _draw_arrow!(plt, 3.55, 2.5, 2.5, 2.5)

    # Downward arrows to Row 3
    _draw_arrow!(plt, 4.2, 1.85, 2.6, 1.25)
    _draw_arrow!(plt, 5.1, 1.85, 5.4, 1.25)
    _draw_arrow!(plt, 8.4, 1.85, 8.5, 1.25)

    annotate!(plt, 5.0, 5.85, text("EclatFIM Modular Architecture and Data Flow", 11, "sans-serif", :black, :center))

    save_figure(plt, "F02_architecture")
    return true
end

function main(args::Vector{String})
    targets = isempty(args) ? ["f02", "f11", "f03", "f04", "f05", "f06", "f07", "f09"] : lowercase.(args)
    println("Vẽ hình vào $FIGURES_DIR...")
    drawn = 0
    "f02" in targets && (drawn += plot_f02_architecture() ? 1 : 0)
    "f11" in targets && (drawn += plot_f11_groceries() ? 1 : 0)
    "f03" in targets && (drawn += plot_f03_time_vs_minsup() ? 1 : 0)
    "f04" in targets && (drawn += plot_f04_itemsets_vs_minsup() ? 1 : 0)
    "f05" in targets && (drawn += plot_f05_memory() ? 1 : 0)
    "f06" in targets && (drawn += plot_f06_scalability() ? 1 : 0)
    "f07" in targets && (drawn += plot_f07_tx_length() ? 1 : 0)
    "f09" in targets && (drawn += plot_f09_vs_apriori_fp() ? 1 : 0)
    println("Hoàn tất: đã vẽ $drawn bộ hình.")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
