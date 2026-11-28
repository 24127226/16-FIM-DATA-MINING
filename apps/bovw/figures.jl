# Ứng dụng 2, bước 3: vẽ hình để diễn giải các mẫu trực quan (phần của A).
#
#   julia --project=apps apps/bovw/figures.jl          (chạy sau apps/bovw/analyze.jl)
#
#   F12  ảnh kiểm tra của từng lớp, khoanh các mảnh thuộc mẫu đặc trưng số 1 của lớp đó
#        → results/figures/F12_bovw_patterns_on_images.pdf/.png
#   F13  "chân dung" các visual word trong mẫu đặc trưng: 6 mảnh ảnh huấn luyện gần tâm cụm nhất
#        → results/figures/F13_bovw_visual_words.pdf/.png

using Serialization, Random, LinearAlgebra   # đọc cache; norm (khoảng cách tới tâm cụm)
include(joinpath(@__DIR__, "features.jl"))   # load_gray, resize_long_side
include(joinpath(@__DIR__, "..", "..", "scripts", "common.jl"))   # rootpath
haskey(ENV, "GKSwstype") || (ENV["GKSwstype"] = "100")   # máy không có màn hình (Colab): vẽ thẳng ra file
using Plots   # chỉ dùng để vẽ hình
gr()   # bộ vẽ GR
default(fontfamily = "sans-serif", titlefontsize = 8, framestyle = :none, dpi = 200)   # không khung, không trục: hình ảnh

const CACHE = rootpath("data", "apps", "caltech101", "cache")   # kết quả của prepare.jl, analyze.jl
const FIGDIR = rootpath("results", "figures")   # nơi lưu hình
const PALETTE = [RGB(0.90, 0.10, 0.10), RGB(0.10, 0.45, 0.95), RGB(0.10, 0.70, 0.20), RGB(0.95, 0.60, 0.05)]   # đỏ, xanh dương, xanh lá, cam: từ thứ 1, 2, 3, 4 của mẫu

"""Mã item → visual word gốc (phương án "≥ 2 lần" dùng mã k + w cho từ w xuất hiện từ 2 lần)."""
base_word(item, k) = item > k ? item - k : item   # item k + w ("w xuất hiện ≥ 2 lần") → từ w

function save(p, name)   # lưu PDF và PNG
    mkpath(FIGDIR)   # tạo thư mục
    savefig(p, joinpath(FIGDIR, name * ".pdf"))   # bản cho báo cáo
    savefig(p, joinpath(FIGDIR, name * ".png"))   # bản cho notebook
    println("  saved ", name)   # thông báo
end

# [VẤN ĐÁP] figures.jl — hình F12, F13
# LÀM GÌ    : F12 khoanh các mảnh thuộc mẫu số 1 của mỗi lớp trên ảnh kiểm tra; F13 cho 6 mảnh điển hình của mỗi từ.
# VÌ SAO    : để DIỄN GIẢI mẫu bằng mắt: máy bay = cạnh ngang + dải tối + vùng phẳng; đồng hồ = sọc chéo lặp lại của dây.
# HỎI–ĐÁP   : H: Mẫu của Faces_easy có đúng là khuôn mặt không? Đ: không hoàn toàn: từ 73, 113 là cạnh dọc ở mép ảnh và phông
#             nền; nhiều ảnh khuôn mặt của Caltech-101 có phông nền giống nhau. Mẫu phổ biến làm lộ thiên lệch dữ liệu này.
function main()   # vẽ F12 rồi F13
    F = deserialize(joinpath(CACHE, "features.jls"))   # ảnh, nhãn, vị trí các mảnh
    A = deserialize(joinpath(CACHE, "analysis.jls"))   # phương án đã chọn và các mẫu đặc trưng
    k = A.k   # kích thước codebook đã chọn
    cb = deserialize(joinpath(CACHE, "codebook_k$(k).jls"))   # tâm cụm và từ của mọi mảnh
    words = cb.words   # words[j]: từ của mảnh j
    nimg = length(F.files)   # số ảnh
    cols_of = [Int[] for _ in 1:nimg]                  # các mảnh (cột của D) thuộc từng ảnh
    for j in eachindex(F.owner)   # phân các mảnh về ảnh của chúng
        push!(cols_of[F.owner[j]], j)   # (tiếp)
    end
    loadimg(i) = resize_long_side(load_gray(F.files[i]), 256)   # đọc lại ảnh i đúng cỡ đã dùng khi trích mảnh

    # ---- F12: ảnh kiểm tra có chứa mẫu số 1 của lớp, khoanh các mảnh thuộc mẫu ----
    panels = []
    for (c, cname) in enumerate(F.classes)   # từng lớp
        top = A.per_class[c][1]   # các mẫu đặc trưng của lớp (đã xếp theo GR)
        isempty(top) && continue   # lớp không có mẫu thì bỏ qua
        pat = top[1]   # mẫu số 1
        ws = unique(base_word.(pat.items, k))   # các từ thị giác của mẫu
        hits = [i for i in 1:nimg if !F.train[i] && F.labels[i] == c && issubset(pat.items, A.txs[i])]   # ảnh KIỂM TRA của lớp có chứa mẫu
        isempty(hits) && (hits = [i for i in 1:nimg if F.labels[i] == c && issubset(pat.items, A.txs[i])])   # không có thì lấy cả ảnh huấn luyện
        for i in hits[1:min(2, length(hits))]   # vẽ 2 ảnh mỗi lớp
            img = loadimg(i)   # đọc ảnh
            lbl = join((it > k ? "$(it - k)×2" : string(it) for it in pat.items), ", ")   # w×2: từ w xuất hiện ≥ 2 lần
            p = plot(Gray.(img); title = "$cname, image $(basename(F.files[i]))\npattern {$lbl}",   # vẽ ảnh xám, tiêu đề ghi mẫu
                     aspect_ratio = :equal, axis = false, ticks = false)   # (tiếp)
            for j in cols_of[i]   # từng mảnh của ảnh
                w = words[j]   # từ của mảnh
                t = findfirst(==(w), ws)   # từ này là từ thứ mấy của mẫu?
                t === nothing && continue   # không thuộc mẫu: không vẽ
                y, x = F.pos[j]   # góc trên-trái của mảnh
                plot!(p, Shape([x, x + 16, x + 16, x, x], [y, y, y + 16, y + 16, y]); fillalpha = 0,   # khung vuông 16×16 quanh mảnh
                      linecolor = PALETTE[mod1(t, length(PALETTE))], linewidth = 1.5, label = false)   # màu theo thứ tự từ trong mẫu
            end
            push!(panels, p)   # thêm ô hình
        end
    end
    save(plot(panels...; layout = (2, cld(length(panels), 2)), size = (1200, 560)), "F12_bovw_patterns_on_images")   # ghép và lưu F12

    # ---- F13: chân dung visual word: 6 mảnh huấn luyện gần tâm cụm nhất ----
    rows = Matrix{Float32}[]
    labels = String[]   # tiêu đề từng dải
    cache_img = Dict{Int,Matrix{Float32}}()   # ảnh đã đọc (tránh đọc lại)
    getimg(i) = get!(() -> loadimg(i), cache_img, i)   # đọc ảnh i một lần
    for (c, cname) in enumerate(F.classes)   # từng lớp
        isempty(A.per_class[c][1]) && continue   # lớp không có mẫu
        pat = A.per_class[c][1][1]   # mẫu số 1 của lớp
        for w in unique(base_word.(pat.items, k))   # từng từ của mẫu
            cand = [j for j in eachindex(words) if words[j] == w && F.train[F.owner[j]]]   # mảnh huấn luyện thuộc từ w
            dist = [norm(view(F.D, :, j) .- view(cb.C, :, w)) for j in cand]   # khoảng cách tới tâm cụm
            best = cand[sortperm(dist)][1:min(6, length(cand))]   # 6 mảnh gần tâm nhất = "điển hình" của từ
            strip_ = fill(1.0f0, 18, 18 * 6)   # dải trắng chứa 6 mảnh, viền 1 điểm ảnh
            for (t, j) in enumerate(best)   # từng mảnh
                img = getimg(F.owner[j])   # ảnh chứa mảnh
                y, x = F.pos[j]   # góc trên-trái của mảnh
                strip_[2:17, (t - 1) * 18 + 2:(t - 1) * 18 + 17] = img[y:y + 15, x:x + 15]   # chép mảnh 16×16 vào dải
            end
            push!(rows, strip_)   # thêm dải
            push!(labels, "$cname: word $w")   # tiêu đề dải
        end
    end
    tiles = [plot(Gray.(r); title = l, aspect_ratio = :equal, axis = false, ticks = false) for (r, l) in zip(rows, labels)]   # mỗi dải một ô
    save(plot(tiles...; layout = (cld(length(tiles), 2), 2), size = (1000, 118 * cld(length(tiles), 2) + 40), margin = 0Plots.mm),   # ghép 2 cột
         "F13_bovw_visual_words")   # lưu F13
end

main()   # chạy
