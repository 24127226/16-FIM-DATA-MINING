# Ứng dụng 2, bước 1: chọn ảnh, trích descriptor, dựng codebook bằng k-means (phần của A).
#
#   julia --project=apps apps/bovw/prepare.jl
#
# - Dữ liệu: Caltech-101 (Fei-Fei và cộng sự, 2004; giấy phép CC BY 4.0), tải bằng
#   scripts/fetch_data.jl caltech. Chọn 4 lớp có hình dạng khác nhau; mỗi lớp lấy ngẫu nhiên
#   (seed cố định) tối đa 100 ảnh, chia 70% huấn luyện / 30% kiểm tra theo từng lớp.
# - Mỗi ảnh: chuyển xám, thu nhỏ cạnh dài về 256 điểm ảnh, lấy 150 mảnh 16×16 có gradient mạnh nhất
#   trên lưới bước 8, mỗi mảnh một descriptor 128 chiều (features.jl).
# - Codebook: k-means++ trên tối đa 40.000 descriptor của ẢNH HUẤN LUYỆN (tránh rò rỉ dữ liệu kiểm tra),
#   với k ∈ {100, 200, 500}; sau đó gán mọi descriptor về visual word gần nhất.
# Kết quả lưu vào data/apps/caltech101/cache/ (không commit; chạy lại sẽ cho cùng kết quả).

using Random, Serialization
include(joinpath(@__DIR__, "features.jl"))
include(joinpath(@__DIR__, "..", "..", "scripts", "common.jl"))

const SEED = 42
const CLASSES = ["airplanes", "Motorbikes", "Faces_easy", "watch"]
const PER_CLASS = 100
const TRAIN_FRAC = 0.7
const MAXSIDE = 256
const KS = [100, 200, 500]
const KMEANS_SAMPLE = 40_000

const BASE = rootpath("data", "apps", "caltech101")
const IMG_DIR = joinpath(BASE, "101_ObjectCategories")
const CACHE = joinpath(BASE, "cache")

"""
Lệnh tar: trên Windows dùng tar.exe có sẵn của hệ điều hành (bsdtar, đọc được cả zip lẫn tar.gz).
Không dùng bản GNU tar đi kèm Git Bash vì nó hiểu `D:` trong đường dẫn là tên máy từ xa.
"""
function tar_cmd()
    if Sys.iswindows()
        sys = joinpath(get(ENV, "SystemRoot", "C:\\Windows"), "System32", "tar.exe")
        isfile(sys) && return sys
    end
    return "tar"
end

"""Giải nén đúng các lớp cần dùng từ caltech-101.zip (zip chứa 101_ObjectCategories.tar.gz)."""
function extract_classes()
    all(isdir(joinpath(IMG_DIR, c)) for c in CLASSES) && return
    zip = joinpath(BASE, "caltech-101.zip")
    isfile(zip) || error("Chưa có $zip: chạy julia --project=. scripts/fetch_data.jl caltech")
    inner = "caltech-101/101_ObjectCategories.tar.gz"
    targz = joinpath(BASE, inner)
    if !isfile(targz)
        println("Giải nén ", inner)
        if Sys.iswindows()
            run(`$(tar_cmd()) -xf $zip -C $BASE $inner`)  # tar của Windows đọc được zip
        else
            run(`unzip -o -q $zip $inner -d $BASE`)
        end
    end
    println("Giải nén các lớp: ", join(CLASSES, ", "))
    run(`$(tar_cmd()) -xzf $targz -C $BASE $(["101_ObjectCategories/" * c for c in CLASSES])`)
end

function main()
    extract_classes()
    mkpath(CACHE)
    rng = MersenneTwister(SEED)
    files = String[]
    labels = Int[]
    train = Bool[]
    for (ci, c) in enumerate(CLASSES)
        fs = sort(filter(f -> endswith(lowercase(f), ".jpg"), readdir(joinpath(IMG_DIR, c))))
        pick = sort(shuffle(rng, fs)[1:min(PER_CLASS, length(fs))])
        ntr = round(Int, TRAIN_FRAC * length(pick))
        trmask = shuffle(rng, vcat(trues(ntr), falses(length(pick) - ntr)))
        append!(files, joinpath.(Ref(joinpath(IMG_DIR, c)), pick))
        append!(labels, fill(ci, length(pick)))
        append!(train, trmask)
        println(rpad(c, 12), length(fs), " ảnh có sẵn → chọn ", length(pick), " (", ntr, " huấn luyện)")
    end

    t = time()
    Ds = Matrix{Float32}[]
    owner = Int[]
    pos = Tuple{Int,Int}[]
    sizes = Tuple{Int,Int}[]
    for (i, f) in enumerate(files)
        img = resize_long_side(load_gray(f), MAXSIDE)
        D, p = dense_descriptors(img; stride = 8, keep = 150)
        push!(Ds, D)
        append!(owner, fill(i, size(D, 2)))
        append!(pos, p)
        push!(sizes, size(img))
    end
    D = reduce(hcat, Ds)
    println("Descriptor: ", size(D, 2), " mảnh từ ", length(files), " ảnh (", round(time() - t; digits = 1), " s)")
    serialize(joinpath(CACHE, "features.jls"),
              (classes = CLASSES, files = files, labels = labels, train = train, D = D, owner = owner,
               pos = pos, sizes = sizes))

    trcols = findall(j -> train[owner[j]], 1:size(D, 2))
    sample = trcols[randperm(MersenneTwister(SEED), length(trcols))[1:min(KMEANS_SAMPLE, length(trcols))]]
    Xs = D[:, sample]
    for k in KS
        t = time()
        C, _ = kmeans(Xs, k; rng = MersenneTwister(SEED + k))
        words = assign_nearest(D, C)
        serialize(joinpath(CACHE, "codebook_k$(k).jls"), (C = C, words = words))
        println("k = ", lpad(k, 3), ": codebook xong (", round(time() - t; digits = 1), " s)")
    end
end

main()
