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

using Random, Serialization   # Random: chọn ảnh, chia tập có seed; Serialization: lưu kết quả cho bước sau
include(joinpath(@__DIR__, "features.jl"))   # đọc ảnh, descriptor, k-means (code của nhóm)
include(joinpath(@__DIR__, "..", "..", "scripts", "common.jl"))   # rootpath: đường dẫn trong repo

const SEED = 42   # seed cố định: chạy lại cho đúng cùng kết quả
const CLASSES = ["airplanes", "Motorbikes", "Faces_easy", "watch"]   # 4 lớp có hình dạng khác nhau rõ
const PER_CLASS = 100   # 100 ảnh mỗi lớp (400 ảnh): đủ để khai thác, chạy nhanh trên Colab
const TRAIN_FRAC = 0.7   # 70% huấn luyện / 30% kiểm tra, chia theo từng lớp
const MAXSIDE = 256   # thu nhỏ cạnh dài về 256 điểm ảnh: ảnh cùng cỡ, tính nhanh
const KS = [100, 200, 500]   # 3 kích thước codebook để so sánh (bảng B11)
const KMEANS_SAMPLE = 40_000   # k-means trên tối đa 40.000 descriptor lấy mẫu: nhanh mà vẫn đại diện

const BASE = rootpath("data", "apps", "caltech101")   # thư mục dữ liệu (không commit)
const IMG_DIR = joinpath(BASE, "101_ObjectCategories")   # ảnh sau khi giải nén
const CACHE = joinpath(BASE, "cache")   # nơi lưu descriptor và codebook

"""
Lệnh tar: trên Windows dùng tar.exe có sẵn của hệ điều hành (bsdtar, đọc được cả zip lẫn tar.gz).
Không dùng bản GNU tar đi kèm Git Bash vì nó hiểu `D:` trong đường dẫn là tên máy từ xa.
"""
function tar_cmd()   # chọn lệnh tar phù hợp hệ điều hành
    if Sys.iswindows()   # Windows
        sys = joinpath(get(ENV, "SystemRoot", "C:\\Windows"), "System32", "tar.exe")   # tar có sẵn của Windows
        isfile(sys) && return sys   # có thì dùng
    end
    return "tar"   # Linux, macOS, Colab
end

"""Giải nén đúng các lớp cần dùng từ caltech-101.zip (zip chứa 101_ObjectCategories.tar.gz)."""
function extract_classes()   # chỉ giải nén 4 lớp cần dùng
    all(isdir(joinpath(IMG_DIR, c)) for c in CLASSES) && return   # đã giải nén rồi thì thôi
    zip = joinpath(BASE, "caltech-101.zip")   # file tải về bằng fetch_data.jl
    isfile(zip) || error("Chưa có $zip: chạy julia --project=. scripts/fetch_data.jl caltech")   # báo lỗi rõ ràng kèm cách sửa
    inner = "caltech-101/101_ObjectCategories.tar.gz"   # file nén lồng bên trong zip
    targz = joinpath(BASE, inner)   # đường dẫn sau khi lấy ra
    if !isfile(targz)   # chưa lấy ra thì lấy
        println("Giải nén ", inner)   # thông báo
        if Sys.iswindows()   # Windows
            run(`$(tar_cmd()) -xf $zip -C $BASE $inner`)  # tar của Windows đọc được zip
        else
            run(`unzip -o -q $zip $inner -d $BASE`)   # Linux: dùng unzip
        end
    end
    println("Giải nén các lớp: ", join(CLASSES, ", "))   # thông báo
    run(`$(tar_cmd()) -xzf $targz -C $BASE $(["101_ObjectCategories/" * c for c in CLASSES])`)   # giải nén đúng 4 thư mục lớp
end

# [VẤN ĐÁP] prepare.jl — từ ảnh đến từ thị giác
# LÀM GÌ    : chọn 400 ảnh (4 lớp × 100), chia 70/30, trích 150 descriptor 128 chiều/ảnh, học codebook k ∈ {100, 200, 500}.
# VÌ SAO    : Eclat chỉ khai thác được giao dịch; mỗi ảnh phải thành một tập item = tập từ thị giác (bag of visual words).
# HỎI–ĐÁP   : H: Vì sao k-means chỉ học trên ảnh huấn luyện? Đ: để không rò rỉ thông tin ảnh kiểm tra vào biểu diễn;
#             ảnh kiểm tra chỉ được GÁN vào từ đã học, nên độ chính xác ở bảng B13 là đánh giá công bằng.
#             H: Vì sao chọn 4 lớp này? Đ: hình dạng khác nhau rõ (thân dài, khung xe, khuôn mặt, mặt tròn + dây kim loại),
#             dễ kiểm tra bằng mắt xem mẫu tìm được có hợp lý không. Thời gian: bước này khoảng 1 phút.
function main()   # chọn ảnh → descriptor → codebook
    extract_classes()   # bảo đảm có ảnh
    mkpath(CACHE)   # tạo thư mục lưu
    rng = MersenneTwister(SEED)   # bộ sinh số ngẫu nhiên có seed
    files = String[]   # đường dẫn các ảnh được chọn
    labels = Int[]   # nhãn lớp (1..4) của từng ảnh
    train = Bool[]   # true: ảnh huấn luyện; false: ảnh kiểm tra
    for (ci, c) in enumerate(CLASSES)   # từng lớp
        fs = sort(filter(f -> endswith(lowercase(f), ".jpg"), readdir(joinpath(IMG_DIR, c))))   # mọi ảnh JPEG của lớp, sắp theo tên để tái lập
        pick = sort(shuffle(rng, fs)[1:min(PER_CLASS, length(fs))])   # chọn ngẫu nhiên 100 ảnh
        ntr = round(Int, TRAIN_FRAC * length(pick))   # số ảnh huấn luyện = 70
        trmask = shuffle(rng, vcat(trues(ntr), falses(length(pick) - ntr)))   # chia ngẫu nhiên 70/30 trong lớp
        append!(files, joinpath.(Ref(joinpath(IMG_DIR, c)), pick))   # lưu đường dẫn
        append!(labels, fill(ci, length(pick)))   # lưu nhãn
        append!(train, trmask)   # lưu cách chia
        println(rpad(c, 12), length(fs), " ảnh có sẵn → chọn ", length(pick), " (", ntr, " huấn luyện)")   # thông báo
    end

    t = time()   # bấm giờ
    Ds = Matrix{Float32}[]   # descriptor của từng ảnh
    owner = Int[]   # owner[j]: ảnh chứa mảnh j
    pos = Tuple{Int,Int}[]   # pos[j]: vị trí mảnh j (để vẽ F12)
    sizes = Tuple{Int,Int}[]   # kích thước từng ảnh (để tính góc phần tư)
    for (i, f) in enumerate(files)   # từng ảnh
        img = resize_long_side(load_gray(f), MAXSIDE)   # đọc, chuyển xám, thu nhỏ
        D, p = dense_descriptors(img; stride = 8, keep = 150)   # 150 mảnh nhiều cạnh nhất, mỗi mảnh 128 số
        push!(Ds, D)   # lưu
        append!(owner, fill(i, size(D, 2)))   # ghi chủ của từng mảnh
        append!(pos, p)   # ghi vị trí
        push!(sizes, size(img))   # ghi kích thước
    end
    D = reduce(hcat, Ds)   # ghép thành một ma trận 128 × 60.000
    println("Descriptor: ", size(D, 2), " mảnh từ ", length(files), " ảnh (", round(time() - t; digits = 1), " s)")   # thông báo
    serialize(joinpath(CACHE, "features.jls"),   # lưu cho analyze.jl, figures.jl
              (classes = CLASSES, files = files, labels = labels, train = train, D = D, owner = owner,   # (tiếp)
               pos = pos, sizes = sizes))   # (tiếp)

    trcols = findall(j -> train[owner[j]], 1:size(D, 2))   # CHỈ các mảnh của ảnh huấn luyện
    sample = trcols[randperm(MersenneTwister(SEED), length(trcols))[1:min(KMEANS_SAMPLE, length(trcols))]]   # lấy mẫu 40.000 mảnh
    Xs = D[:, sample]   # dữ liệu cho k-means
    for k in KS   # từng kích thước codebook
        t = time()   # bấm giờ
        C, _ = kmeans(Xs, k; rng = MersenneTwister(SEED + k))   # học k tâm cụm (k từ thị giác)
        words = assign_nearest(D, C)   # gán MỌI mảnh (cả ảnh kiểm tra) vào từ gần nhất
        serialize(joinpath(CACHE, "codebook_k$(k).jls"), (C = C, words = words))   # lưu codebook
        println("k = ", lpad(k, 3), ": codebook xong (", round(time() - t; digits = 1), " s)")   # thông báo
    end
end

main()   # chạy
