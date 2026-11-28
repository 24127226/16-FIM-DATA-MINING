# Ứng dụng 2: đọc ảnh, descriptor gradient dày đặc, k-means++ (phần của A).
# Mọi bước trích đặc trưng đều do nhóm tự viết. Thư viện ngoài: JpegTurbo.jl (giải mã file JPEG),
# ColorTypes.jl (đổi điểm ảnh màu sang độ sáng); LinearAlgebra là thư viện chuẩn (nhân ma trận BLAS, chuẩn L2).
#
# Vì sao cần file này: Eclat chỉ làm việc trên giao dịch (tập item). Để khai thác ảnh, mỗi ảnh phải được
# biến thành một tập "từ thị giác" (visual word): cắt ảnh thành các mảnh nhỏ, mô tả mỗi mảnh bằng một vector
# số (descriptor), gom các vector giống nhau thành k cụm (k-means); mỗi cụm là một từ thị giác.

using JpegTurbo, ColorTypes, LinearAlgebra, Random   # giải mã JPEG; điểm ảnh; BLAS, norm; rand

# ---------------------------------------------------------------------------
# Ảnh
# ---------------------------------------------------------------------------

"""Đọc ảnh JPEG thành ma trận độ sáng Float32 trong [0, 1] (ảnh màu được chuyển sang ảnh xám)."""
function load_gray(path::AbstractString)   # đọc một ảnh
    img = JpegTurbo.jpeg_decode(path)                      # ma trận điểm ảnh (màu RGB hoặc xám)
    return Float32[Float32(gray(Gray(px))) for px in img]  # mỗi điểm ảnh → độ sáng trong [0, 1]
end

"""Thu nhỏ ảnh (nội suy song tuyến) để cạnh dài nhất bằng `maxside` điểm ảnh; ảnh nhỏ hơn giữ nguyên."""
function resize_long_side(img::Matrix{Float32}, maxside::Int)   # thu nhỏ ảnh
    h, w = size(img)                                       # chiều cao, chiều rộng
    s = maxside / max(h, w)                                # hệ số thu nhỏ
    s >= 1 && return img                                   # ảnh đã đủ nhỏ: giữ nguyên
    nh, nw = max(1, round(Int, h * s)), max(1, round(Int, w * s))   # kích thước mới
    out = Matrix{Float32}(undef, nh, nw)   # ảnh mới
    @inbounds for j in 1:nw, i in 1:nh                     # với mỗi điểm ảnh của ảnh mới
        y = clamp((i - 0.5) / s + 0.5, 1.0, Float64(h))    # tọa độ tương ứng (số thực) trên ảnh gốc
        x = clamp((j - 0.5) / s + 0.5, 1.0, Float64(w))   # (tương tự theo chiều ngang)
        y0, x0 = floor(Int, y), floor(Int, x)              # điểm ảnh gốc ở góc trên-trái
        y1, x1 = min(y0 + 1, h), min(x0 + 1, w)            # điểm ảnh gốc ở góc dưới-phải
        dy, dx = Float32(y - y0), Float32(x - x0)          # khoảng cách tới góc trên-trái (trọng số nội suy)
        out[i, j] = (1 - dy) * ((1 - dx) * img[y0, x0] + dx * img[y0, x1]) +   # trung bình có trọng số
                    dy * ((1 - dx) * img[y1, x0] + dx * img[y1, x1])           # của 4 điểm ảnh gần nhất
    end
    return out   # kết quả (ảnh đã thu nhỏ / chỉ số tâm gần nhất của mọi điểm)
end

# ---------------------------------------------------------------------------
# Descriptor: biểu đồ hướng gradient trên lưới dày đặc (ý tưởng của SIFT/HOG, bản rút gọn)
# ---------------------------------------------------------------------------

const PATCH = 16          # mảnh 16×16 điểm ảnh
const CELLS = 4           # chia 4×4 ô, mỗi ô 4×4 điểm ảnh
const BINS = 8            # 8 hướng gradient mỗi ô → descriptor 4·4·8 = 128 chiều
const DIM = CELLS * CELLS * BINS   # số chiều của một descriptor = 128

"""Độ lớn và hướng gradient (sai phân trung tâm) tại mọi điểm ảnh."""
function gradients(img::Matrix{Float32})   # cạnh của ảnh tại mọi điểm
    h, w = size(img)   # kích thước ảnh
    mag = Matrix{Float32}(undef, h, w)                     # độ lớn gradient (độ mạnh của cạnh)
    bin = Matrix{Int8}(undef, h, w)                        # hướng gradient, lượng tử hóa thành 1..8
    @inbounds for j in 1:w, i in 1:h   # mọi điểm ảnh
        gx = img[i, min(j + 1, w)] - img[i, max(j - 1, 1)] # độ chênh sáng theo chiều ngang
        gy = img[min(i + 1, h), j] - img[max(i - 1, 1), j] # độ chênh sáng theo chiều dọc
        mag[i, j] = sqrt(gx * gx + gy * gy)                # độ lớn của vector gradient
        θ = atan(gy, gx) + Float32(π)                      # [0, 2π]
        bin[i, j] = Int8(min(BINS - 1, floor(Int, θ / (2π) * BINS)) + 1)   # góc → một trong 8 hướng
    end
    return mag, bin   # độ lớn và hướng
end

# [VẤN ĐÁP] dense_descriptors — descriptor tự viết (ý tưởng SIFT/HOG)
# LÀM GÌ    : mảnh 16×16 → 4×4 ô × 8 hướng gradient = 128 số; giữ 150 mảnh nhiều cạnh nhất; chuẩn hóa L2, cắt 0,2, chuẩn hóa lại.
# HỎI–ĐÁP   : H: Vì sao không dùng thư viện SIFT? Đ: thầy cho phép thư viện ở bước tiền xử lý, nhưng tự viết bản rút gọn thì
#             giải thích được từng bước và không phụ thuộc thư viện C khó cài trên Colab. H: Vì sao bỏ mảnh phẳng? Đ: vùng nền
#             phẳng không mang thông tin hình dạng, giữ lại chỉ sinh ra các từ chung chung.
"""
    dense_descriptors(img; stride, keep) -> (D, pos)

Trích descriptor 128 chiều cho các mảnh 16×16 trên lưới bước `stride`, chỉ giữ `keep` mảnh có
"năng lượng" gradient lớn nhất (bỏ nền phẳng, ít thông tin). Mỗi descriptor được chuẩn hóa L2,
cắt ở 0,2 rồi chuẩn hóa lại như SIFT (Lowe, 2004) để bớt nhạy với độ tương phản.
`D` là ma trận 128 × n; `pos[k]` là góc trên-trái (hàng, cột) của mảnh k.
"""
function dense_descriptors(img::Matrix{Float32}; stride::Int = 8, keep::Int = 150)   # descriptor của các mảnh nhiều cạnh nhất
    h, w = size(img)   # kích thước ảnh
    mag, bin = gradients(img)   # tính gradient một lần cho cả ảnh
    cand = Tuple{Float32,Int,Int}[]                        # (năng lượng, hàng, cột) của các mảnh ứng viên
    for x in 1:stride:(w - PATCH + 1), y in 1:stride:(h - PATCH + 1)   # duyệt lưới, bước `stride` điểm ảnh
        e = 0.0f0                                          # năng lượng = tổng độ lớn gradient trong mảnh
        @inbounds for j in x:(x + PATCH - 1), i in y:(y + PATCH - 1)   # mọi điểm của mảnh
            e += mag[i, j]   # cộng độ lớn cạnh
        end
        e > 1.0f0 && push!(cand, (e, y, x))                # bỏ mảnh gần như phẳng (không có cạnh)
    end
    sort!(cand; rev = true)                                # mảnh nhiều cạnh nhất đứng đầu
    n = min(keep, length(cand))                            # giữ tối đa `keep` mảnh
    D = zeros(Float32, DIM, n)                             # mỗi cột là descriptor của một mảnh
    pos = Vector{Tuple{Int,Int}}(undef, n)   # vị trí các mảnh được giữ
    cell = PATCH ÷ CELLS                                   # cạnh của một ô = 4 điểm ảnh
    @inbounds for k in 1:n   # từng mảnh được giữ
        _, y, x = cand[k]   # vị trí của mảnh
        pos[k] = (y, x)                                    # nhớ vị trí để vẽ hình F12
        for cx in 0:(CELLS-1), cy in 0:(CELLS-1)           # 16 ô của mảnh
            base = (cy * CELLS + cx) * BINS                # vị trí 8 phần tử của ô này trong descriptor
            for j in (x + cx * cell):(x + cx * cell + cell - 1), i in (y + cy * cell):(y + cy * cell + cell - 1)   # mọi điểm của ô
                D[base + bin[i, j], k] += mag[i, j]        # cộng độ lớn gradient vào đúng hướng của nó
            end
        end
        v = view(D, :, k)                                  # descriptor của mảnh k (không sao chép)
        v ./= max(norm(v), 1.0f-6)                         # chuẩn hóa L2: bỏ ảnh hưởng của độ tương phản
        clamp!(v, 0.0f0, 0.2f0)                            # cắt giá trị lớn: một cạnh rất mạnh không lấn át cả mảnh
        v ./= max(norm(v), 1.0f-6)                         # chuẩn hóa lại sau khi cắt
    end
    return D, pos   # ma trận descriptor và vị trí
end

# ---------------------------------------------------------------------------
# k-means++ (Arthur & Vassilvitskii, 2007) + Lloyd; khoảng cách tính bằng phép nhân ma trận (BLAS)
# ---------------------------------------------------------------------------

"""Khởi tạo k tâm cụm: chọn lần lượt, xác suất tỉ lệ với bình phương khoảng cách tới tâm gần nhất."""
function kmeanspp(X::Matrix{Float32}, k::Int, rng)   # khởi tạo k-means++
    d, n = size(X)                                         # d chiều, n điểm (mỗi cột một điểm)
    C = Matrix{Float32}(undef, d, k)                       # k tâm cụm
    C[:, 1] = X[:, rand(rng, 1:n)]                         # tâm đầu tiên: một điểm ngẫu nhiên
    d2 = vec(sum(abs2, X .- C[:, 1]; dims = 1))            # bình phương khoảng cách mỗi điểm tới tâm gần nhất
    for c in 2:k   # chọn tâm thứ 2..k
        r = rand(rng) * sum(d2)                            # chọn điểm với xác suất tỉ lệ d2: điểm xa dễ được chọn
        idx = something(findfirst(>=(r), cumsum(d2)), n)   # điểm được chọn (lấy mẫu theo trọng số d2)
        C[:, c] = X[:, idx]   # thành tâm mới
        @inbounds for j in 1:n                             # cập nhật khoảng cách tới tâm gần nhất
            s = 0.0f0   # bình phương khoảng cách tới tâm mới
            for t in 1:d   # cộng theo từng chiều
                δ = X[t, j] - C[t, c]   # chênh lệch một chiều
                s += δ * δ   # cộng bình phương
            end
            d2[j] = min(d2[j], s)   # giữ khoảng cách tới tâm GẦN NHẤT
        end
    end
    return C   # k tâm khởi tạo
end

"""Gán mỗi cột của X vào tâm gần nhất: ‖x − c‖² = ‖x‖² + ‖c‖² − 2 xᵀc, phần xᵀc tính bằng BLAS theo khối."""
function assign_nearest(X::Matrix{Float32}, C::Matrix{Float32}; chunk::Int = 20_000)   # gán mỗi điểm vào tâm gần nhất
    n = size(X, 2)   # số điểm
    k = size(C, 2)   # số tâm
    cn = vec(sum(abs2, C; dims = 1))                       # ‖c‖² của từng tâm (‖x‖² như nhau cho mọi tâm nên bỏ qua)
    out = Vector{Int}(undef, n)                            # out[j] = chỉ số tâm gần điểm j nhất
    G = Matrix{Float32}(undef, k, min(chunk, n))           # vùng nhớ cho tích Cᵀ X của một khối điểm
    for s in 1:chunk:n                                     # xử lý từng khối `chunk` điểm để không tốn quá nhiều RAM
        e = min(s + chunk - 1, n)   # cuối khối
        Gv = view(G, :, 1:(e - s + 1))   # phần dùng của vùng nhớ G
        mul!(Gv, transpose(C), view(X, :, s:e))            # Gv[c, j] = cᵀ x_j, tính bằng BLAS (rất nhanh)
        @inbounds for j in 1:(e - s + 1)   # từng điểm của khối
            best, bi = Inf32, 1   # khoảng cách nhỏ nhất và tâm tương ứng
            for c in 1:k   # xét mọi tâm
                v = cn[c] - 2 * Gv[c, j]                   # ‖x − c‖² − ‖x‖²: so sánh được giữa các tâm
                v < best && ((best, bi) = (v, c))   # gần hơn thì cập nhật
            end
            out[s + j - 1] = bi   # ghi tâm gần nhất
        end
    end
    return out   # kết quả (ảnh đã thu nhỏ / chỉ số tâm gần nhất của mọi điểm)
end

# [VẤN ĐÁP] kmeans — dựng codebook
# HỎI–ĐÁP   : H: Vì sao k-means++? Đ: chọn tâm khởi tạo rải đều (xác suất tỉ lệ bình phương khoảng cách), hội tụ nhanh và ổn định
#             hơn chọn ngẫu nhiên. H: assign_nearest nhanh nhờ đâu? Đ: ‖x − c‖² = ‖x‖² + ‖c‖² − 2xᵀc, phần xᵀc là phép nhân ma trận
#             tính bằng BLAS theo khối 20.000 điểm.
"""
    kmeans(X, k; rng, iters = 40) -> (C, assign)

k-means với khởi tạo k-means++ và các vòng lặp Lloyd; dừng khi < 0,1% điểm đổi cụm.
Cụm rỗng được khởi tạo lại bằng một điểm ngẫu nhiên (có seed).
"""
function kmeans(X::Matrix{Float32}, k::Int; rng, iters::Int = 40)   # k-means: khởi tạo ++ rồi lặp Lloyd
    d, n = size(X)   # d chiều, n điểm
    C = kmeanspp(X, k, rng)                                # khởi tạo tâm
    assign = zeros(Int, n)                                 # cụm của từng điểm (0 = chưa gán)
    for it in 1:iters   # tối đa 40 vòng
        new = assign_nearest(X, C)                         # bước 1: gán mỗi điểm vào tâm gần nhất
        changed = count(new .!= assign)                    # số điểm đổi cụm so với vòng trước
        assign = new   # gán mới
        fill!(C, 0)                                        # bước 2: tính lại tâm = trung bình các điểm của cụm
        cnt = zeros(Int, k)   # số điểm của từng cụm
        @inbounds for j in 1:n   # cộng dồn điểm vào cụm của nó
            a = assign[j]   # cụm của điểm j
            cnt[a] += 1   # đếm
            for t in 1:d   # cộng theo từng chiều
                C[t, a] += X[t, j]   # cộng tọa độ
            end
        end
        for c in 1:k   # xét mọi tâm
            if cnt[c] == 0   # cụm rỗng
                C[:, c] = X[:, rand(rng, 1:n)]             # cụm rỗng: đặt lại tâm bằng một điểm ngẫu nhiên
            else
                C[:, c] ./= cnt[c]   # tổng → trung bình
            end
        end
        changed <= 0.001n && break                         # hội tụ: dưới 0,1% điểm đổi cụm
    end
    return C, assign   # tâm và cụm của từng điểm
end
