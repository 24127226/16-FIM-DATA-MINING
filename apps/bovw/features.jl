# Ứng dụng 2: đọc ảnh, descriptor gradient dày đặc, k-means++ (phần của A).
# Mọi bước trích đặc trưng đều do nhóm tự viết; thư viện ngoài chỉ dùng để giải mã file JPEG.

using JpegTurbo, ColorTypes, LinearAlgebra, Random

# ---------------------------------------------------------------------------
# Ảnh
# ---------------------------------------------------------------------------

"""Đọc ảnh JPEG thành ma trận độ sáng Float32 trong [0, 1] (ảnh màu được chuyển sang ảnh xám)."""
function load_gray(path::AbstractString)
    img = JpegTurbo.jpeg_decode(path)
    return Float32[Float32(gray(Gray(px))) for px in img]
end

"""Thu nhỏ ảnh (nội suy song tuyến) để cạnh dài nhất bằng `maxside` điểm ảnh; ảnh nhỏ hơn giữ nguyên."""
function resize_long_side(img::Matrix{Float32}, maxside::Int)
    h, w = size(img)
    s = maxside / max(h, w)
    s >= 1 && return img
    nh, nw = max(1, round(Int, h * s)), max(1, round(Int, w * s))
    out = Matrix{Float32}(undef, nh, nw)
    @inbounds for j in 1:nw, i in 1:nh
        y = clamp((i - 0.5) / s + 0.5, 1.0, Float64(h))
        x = clamp((j - 0.5) / s + 0.5, 1.0, Float64(w))
        y0, x0 = floor(Int, y), floor(Int, x)
        y1, x1 = min(y0 + 1, h), min(x0 + 1, w)
        dy, dx = Float32(y - y0), Float32(x - x0)
        out[i, j] = (1 - dy) * ((1 - dx) * img[y0, x0] + dx * img[y0, x1]) +
                    dy * ((1 - dx) * img[y1, x0] + dx * img[y1, x1])
    end
    return out
end

# ---------------------------------------------------------------------------
# Descriptor: biểu đồ hướng gradient trên lưới dày đặc (ý tưởng của SIFT/HOG, bản rút gọn)
# ---------------------------------------------------------------------------

const PATCH = 16          # mảnh 16×16 điểm ảnh
const CELLS = 4           # chia 4×4 ô, mỗi ô 4×4 điểm ảnh
const BINS = 8            # 8 hướng gradient mỗi ô → descriptor 4·4·8 = 128 chiều
const DIM = CELLS * CELLS * BINS

"""Độ lớn và hướng gradient (sai phân trung tâm) tại mọi điểm ảnh."""
function gradients(img::Matrix{Float32})
    h, w = size(img)
    mag = Matrix{Float32}(undef, h, w)
    bin = Matrix{Int8}(undef, h, w)
    @inbounds for j in 1:w, i in 1:h
        gx = img[i, min(j + 1, w)] - img[i, max(j - 1, 1)]
        gy = img[min(i + 1, h), j] - img[max(i - 1, 1), j]
        mag[i, j] = sqrt(gx * gx + gy * gy)
        θ = atan(gy, gx) + Float32(π)                      # [0, 2π]
        bin[i, j] = Int8(min(BINS - 1, floor(Int, θ / (2π) * BINS)) + 1)
    end
    return mag, bin
end

"""
    dense_descriptors(img; stride, keep) -> (D, pos)

Trích descriptor 128 chiều cho các mảnh 16×16 trên lưới bước `stride`, chỉ giữ `keep` mảnh có
"năng lượng" gradient lớn nhất (bỏ nền phẳng, ít thông tin). Mỗi descriptor được chuẩn hóa L2,
cắt ở 0,2 rồi chuẩn hóa lại như SIFT (Lowe, 2004) để bớt nhạy với độ tương phản.
`D` là ma trận 128 × n; `pos[k]` là góc trên-trái (hàng, cột) của mảnh k.
"""
function dense_descriptors(img::Matrix{Float32}; stride::Int = 8, keep::Int = 150)
    h, w = size(img)
    mag, bin = gradients(img)
    cand = Tuple{Float32,Int,Int}[]
    for x in 1:stride:(w - PATCH + 1), y in 1:stride:(h - PATCH + 1)
        e = 0.0f0
        @inbounds for j in x:(x + PATCH - 1), i in y:(y + PATCH - 1)
            e += mag[i, j]
        end
        e > 1.0f0 && push!(cand, (e, y, x))
    end
    sort!(cand; rev = true)
    n = min(keep, length(cand))
    D = zeros(Float32, DIM, n)
    pos = Vector{Tuple{Int,Int}}(undef, n)
    cell = PATCH ÷ CELLS
    @inbounds for k in 1:n
        _, y, x = cand[k]
        pos[k] = (y, x)
        for cx in 0:(CELLS-1), cy in 0:(CELLS-1)
            base = (cy * CELLS + cx) * BINS
            for j in (x + cx * cell):(x + cx * cell + cell - 1), i in (y + cy * cell):(y + cy * cell + cell - 1)
                D[base + bin[i, j], k] += mag[i, j]
            end
        end
        v = view(D, :, k)
        v ./= max(norm(v), 1.0f-6)
        clamp!(v, 0.0f0, 0.2f0)
        v ./= max(norm(v), 1.0f-6)
    end
    return D, pos
end

# ---------------------------------------------------------------------------
# k-means++ (Arthur & Vassilvitskii, 2007) + Lloyd; khoảng cách tính bằng phép nhân ma trận (BLAS)
# ---------------------------------------------------------------------------

"""Khởi tạo k tâm cụm: chọn lần lượt, xác suất tỉ lệ với bình phương khoảng cách tới tâm gần nhất."""
function kmeanspp(X::Matrix{Float32}, k::Int, rng)
    d, n = size(X)
    C = Matrix{Float32}(undef, d, k)
    C[:, 1] = X[:, rand(rng, 1:n)]
    d2 = vec(sum(abs2, X .- C[:, 1]; dims = 1))
    for c in 2:k
        r = rand(rng) * sum(d2)
        idx = something(findfirst(>=(r), cumsum(d2)), n)
        C[:, c] = X[:, idx]
        @inbounds for j in 1:n
            s = 0.0f0
            for t in 1:d
                δ = X[t, j] - C[t, c]
                s += δ * δ
            end
            d2[j] = min(d2[j], s)
        end
    end
    return C
end

"""Gán mỗi cột của X vào tâm gần nhất: ‖x − c‖² = ‖x‖² + ‖c‖² − 2 xᵀc, phần xᵀc tính bằng BLAS theo khối."""
function assign_nearest(X::Matrix{Float32}, C::Matrix{Float32}; chunk::Int = 20_000)
    n = size(X, 2)
    k = size(C, 2)
    cn = vec(sum(abs2, C; dims = 1))
    out = Vector{Int}(undef, n)
    G = Matrix{Float32}(undef, k, min(chunk, n))
    for s in 1:chunk:n
        e = min(s + chunk - 1, n)
        Gv = view(G, :, 1:(e - s + 1))
        mul!(Gv, transpose(C), view(X, :, s:e))
        @inbounds for j in 1:(e - s + 1)
            best, bi = Inf32, 1
            for c in 1:k
                v = cn[c] - 2 * Gv[c, j]
                v < best && ((best, bi) = (v, c))
            end
            out[s + j - 1] = bi
        end
    end
    return out
end

"""
    kmeans(X, k; rng, iters = 40) -> (C, assign)

k-means với khởi tạo k-means++ và các vòng lặp Lloyd; dừng khi < 0,1% điểm đổi cụm.
Cụm rỗng được khởi tạo lại bằng một điểm ngẫu nhiên (có seed).
"""
function kmeans(X::Matrix{Float32}, k::Int; rng, iters::Int = 40)
    d, n = size(X)
    C = kmeanspp(X, k, rng)
    assign = zeros(Int, n)
    for it in 1:iters
        new = assign_nearest(X, C)
        changed = count(new .!= assign)
        assign = new
        fill!(C, 0)
        cnt = zeros(Int, k)
        @inbounds for j in 1:n
            a = assign[j]
            cnt[a] += 1
            for t in 1:d
                C[t, a] += X[t, j]
            end
        end
        for c in 1:k
            if cnt[c] == 0
                C[:, c] = X[:, rand(rng, 1:n)]
            else
                C[:, c] ./= cnt[c]
            end
        end
        changed <= 0.001n && break
    end
    return C, assign
end
