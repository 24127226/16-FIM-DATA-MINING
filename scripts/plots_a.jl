# Vẽ các hình phần của A từ CSV trong results/:
#   F08 tỉ số thời gian vector/bitset theo mật độ (E7, giả thuyết H2)
#   F10 bộ nhớ tidset theo tiến trình duyệt (E10, giả thuyết H7)
#
#   julia --project=scripts scripts/plots_a.jl

include(joinpath(@__DIR__, "config.jl"))
include(joinpath(@__DIR__, "plot_style.jl"))

function fig_density()
    rows = read_rows(joinpath(results_dir(), "density.csv"))
    isempty(rows) && return println("  bỏ qua F08: chưa có density.csv")
    p = plot(; xscale = :log10, yscale = :log10, xlabel = "mật độ tidset ρ = σ̄ / N (log)",
             ylabel = "thời gian vector (v3) / bitset (v4)", legend = :topleft,
             title = "Khi nào bitset có lợi hơn vector?")
    hline!(p, [1.0]; color = :black, ls = :dot, label = "hòa")
    vline!(p, [1 / 32]; color = :gray, ls = :dash, label = "ρ = 1/32 (cân bằng bộ nhớ)")
    syn = [r for r in rows if r["source"] == "tong_hop"]
    xs = [numval(r["density"]) for r in syn]
    ys = [numval(r["t_v3"]) / numval(r["t_v4"]) for r in syn]
    plot!(p, xs, ys; label = "dữ liệu tổng hợp", color = :black, marker = :circle, markersize = 3)
    shapes = Dict("benchmark" => :diamond, "ung_dung_1" => :square, "ung_dung_2" => :utriangle)
    names = Dict("benchmark" => "benchmark", "ung_dung_1" => "Groceries (Ứng dụng 1)", "ung_dung_2" => "ảnh (Ứng dụng 2)")
    for src in ("benchmark", "ung_dung_1", "ung_dung_2")
        sel = [r for r in rows if r["source"] == src]
        isempty(sel) && continue
        scatter!(p, [numval(r["density"]) for r in sel], [numval(r["t_v3"]) / numval(r["t_v4"]) for r in sel];
                 label = names[src], marker = shapes[src], markersize = 5)
    end
    for r in rows
        r["source"] == "benchmark" && r["minsup"] == median_minsup(load_grid()[r["dataset"]]) || continue
        annotate!(p, numval(r["density"]), numval(r["t_v3"]) / numval(r["t_v4"]), text("  " * r["dataset"], 6, :left))
    end
    save_figure(plot(p; size = (560, 400)), "F08_mat_do_bitset_vector")
end

function fig_memory_trace()
    rows = read_rows(joinpath(results_dir(), "memory_trace.csv"))
    isempty(rows) && return println("  bỏ qua F10: chưa có memory_trace.csv")
    panels = []
    for ds in unique(r["dataset"] for r in rows)
        ms = first(r["minsup"] for r in rows if r["dataset"] == ds)
        p = plot(; xlabel = "thứ tự tập phổ biến được xuất", ylabel = "tidset đang sống (MiB)",
                 title = "$ds, minsup $ms", legend = :topright)
        for (v, lab) in (("v3", "mảng chỉ số (v3)"), ("v4", "mảng bit (v4)"))
            sel = [r for r in rows if r["dataset"] == ds && r["variant"] == v]
            plot!(p, [numval(r["itemset_index"]) for r in sel], [numval(r["bytes_current"]) / 2^20 for r in sel];
                  label = lab, linewidth = 1.2)
        end
        push!(panels, p)
    end
    save_figure(plot(panels...; layout = (1, length(panels)), size = (520 * length(panels), 340), margin = 3Plots.mm),
                "F10_bo_nho_theo_tien_trinh")
end

fig_density()
fig_memory_trace()
