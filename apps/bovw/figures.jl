# Ứng dụng 2, bước 3: vẽ hình để diễn giải các mẫu trực quan (phần của A).
#
#   julia --project=apps apps/bovw/figures.jl          (chạy sau apps/bovw/analyze.jl)
#
#   F12  ảnh kiểm tra của từng lớp, khoanh các mảnh thuộc mẫu đặc trưng số 1 của lớp đó
#   F13  "chân dung" các visual word trong mẫu đặc trưng: 6 mảnh ảnh huấn luyện gần tâm cụm nhất

using Serialization, Random, LinearAlgebra
include(joinpath(@__DIR__, "features.jl"))
include(joinpath(@__DIR__, "..", "..", "scripts", "common.jl"))
haskey(ENV, "GKSwstype") || (ENV["GKSwstype"] = "100")   # máy không có màn hình (Colab): vẽ thẳng ra file
using Plots
gr()
default(fontfamily = "sans-serif", titlefontsize = 8, framestyle = :none, dpi = 200)

const CACHE = rootpath("data", "apps", "caltech101", "cache")
const FIGDIR = rootpath("results", "figures")
const PALETTE = [RGB(0.90, 0.10, 0.10), RGB(0.10, 0.45, 0.95), RGB(0.10, 0.70, 0.20), RGB(0.95, 0.60, 0.05)]

"""Mã item → visual word gốc (phương án "≥ 2 lần" dùng mã k + w cho từ w xuất hiện từ 2 lần)."""
base_word(item, k) = item > k ? item - k : item

function save(p, name)
    mkpath(FIGDIR)
    savefig(p, joinpath(FIGDIR, name * ".pdf"))
    savefig(p, joinpath(FIGDIR, name * ".png"))
    println("  đã lưu ", name)
end

function main()
    F = deserialize(joinpath(CACHE, "features.jls"))
    A = deserialize(joinpath(CACHE, "analysis.jls"))
    k = A.k
    cb = deserialize(joinpath(CACHE, "codebook_k$(k).jls"))
    words = cb.words
    nimg = length(F.files)
    cols_of = [Int[] for _ in 1:nimg]                  # các mảnh (cột của D) thuộc từng ảnh
    for j in eachindex(F.owner)
        push!(cols_of[F.owner[j]], j)
    end
    loadimg(i) = resize_long_side(load_gray(F.files[i]), 256)

    # ---- F12: ảnh kiểm tra có chứa mẫu số 1 của lớp, khoanh các mảnh thuộc mẫu ----
    panels = []
    for (c, cname) in enumerate(F.classes)
        top = A.per_class[c][1]
        isempty(top) && continue
        pat = top[1]
        ws = unique(base_word.(pat.items, k))
        hits = [i for i in 1:nimg if !F.train[i] && F.labels[i] == c && issubset(pat.items, A.txs[i])]
        isempty(hits) && (hits = [i for i in 1:nimg if F.labels[i] == c && issubset(pat.items, A.txs[i])])
        for i in hits[1:min(2, length(hits))]
            img = loadimg(i)
            lbl = join((it > k ? "$(it - k)×2" : string(it) for it in pat.items), ", ")   # w×2: từ w xuất hiện ≥ 2 lần
            p = plot(Gray.(img); title = "$cname, ảnh $(basename(F.files[i]))\nmẫu {$lbl}",
                     aspect_ratio = :equal, axis = false, ticks = false)
            for j in cols_of[i]
                w = words[j]
                t = findfirst(==(w), ws)
                t === nothing && continue
                y, x = F.pos[j]
                plot!(p, Shape([x, x + 16, x + 16, x, x], [y, y, y + 16, y + 16, y]); fillalpha = 0,
                      linecolor = PALETTE[mod1(t, length(PALETTE))], linewidth = 1.5, label = false)
            end
            push!(panels, p)
        end
    end
    save(plot(panels...; layout = (2, cld(length(panels), 2)), size = (1200, 560)), "F12_mau_truc_quan_tren_anh")

    # ---- F13: chân dung visual word: 6 mảnh huấn luyện gần tâm cụm nhất ----
    rows = Matrix{Float32}[]
    labels = String[]
    cache_img = Dict{Int,Matrix{Float32}}()
    getimg(i) = get!(() -> loadimg(i), cache_img, i)
    for (c, cname) in enumerate(F.classes)
        isempty(A.per_class[c][1]) && continue
        pat = A.per_class[c][1][1]
        for w in unique(base_word.(pat.items, k))
            cand = [j for j in eachindex(words) if words[j] == w && F.train[F.owner[j]]]
            dist = [norm(view(F.D, :, j) .- view(cb.C, :, w)) for j in cand]
            best = cand[sortperm(dist)][1:min(6, length(cand))]
            strip_ = fill(1.0f0, 18, 18 * 6)
            for (t, j) in enumerate(best)
                img = getimg(F.owner[j])
                y, x = F.pos[j]
                strip_[2:17, (t - 1) * 18 + 2:(t - 1) * 18 + 17] = img[y:y + 15, x:x + 15]
            end
            push!(rows, strip_)
            push!(labels, "$cname: từ $w")
        end
    end
    tiles = [plot(Gray.(r); title = l, aspect_ratio = :equal, axis = false, ticks = false) for (r, l) in zip(rows, labels)]
    save(plot(tiles...; layout = (cld(length(tiles), 2), 2), size = (1000, 118 * cld(length(tiles), 2) + 40), margin = 0Plots.mm),
         "F13_chan_dung_visual_word")
end

main()
