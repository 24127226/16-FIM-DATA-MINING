# Bộ sinh dữ liệu giao dịch tổng hợp kiểu IBM Quest cho thí nghiệm E6 (R14, H5).
#
# Cách dùng (từ gốc repo):
#   julia --project=. scripts/gen_synthetic.jl
#   julia --project=. scripts/gen_synthetic.jl --n 5000 --lens 5,10,15   # chạy thử nhanh
#
# Tham số mặc định theo KE_HOACH_DU_AN.md mục 8.4 (E6):
#   m = 1.000, N = 50.000, L̄ ∈ {5, 10, 15, 20, 25, 30}, 500 mẫu tiềm năng độ dài TB 4, seed 42.

using Random
include(joinpath(@__DIR__, "config.jl"))

"""Sinh số nguyên theo phân phối Poisson(λ) bằng thuật toán Knuth (không cần thư viện ngoài)."""
function rand_poisson(rng::AbstractRNG, lambda::Float64)::Int
    L = exp(-lambda)
    k = 0
    p = 1.0
    while p > L
        k += 1
        p *= rand(rng)
    end
    return k - 1
end

"""Chọn chỉ số ngẫu nhiên theo phân phối rời rạc đã tích lũy `cdf`."""
function sample_cdf(rng::AbstractRNG, cdf::Vector{Float64})::Int
    u = rand(rng)
    idx = searchsortedfirst(cdf, u)
    return min(idx, length(cdf))
end

"""Sinh `n_patterns` mẫu tiềm năng có độ dài trung bình `avg_len` và trọng số phân phối mũ."""
function generate_patterns(rng::AbstractRNG, m::Int, n_patterns::Int, avg_len::Float64)
    patterns = Vector{Vector{Int}}(undef, n_patterns)
    weights = Vector{Float64}(undef, n_patterns)
    prev = Int[]
    for i in 1:n_patterns
        len = clamp(rand_poisson(rng, avg_len), 1, min(m, 20))
        pat = Int[]
        # Tương quan nhẹ: giữ lại một phần nhỏ item từ mẫu trước giống IBM generator
        if !isempty(prev) && len > 1
            keep = min(length(prev), floor(Int, len * min(0.5, rand(rng) * 0.5)))
            for j in 1:keep
                push!(pat, prev[j])
            end
        end
        while length(pat) < len
            item = rand(rng, 1:m)
            item in pat || push!(pat, item)
        end
        sort!(pat)
        patterns[i] = pat
        weights[i] = -log(max(rand(rng), 1e-12))   # phân phối mũ Exp(1)
        prev = pat
    end
    total_w = sum(weights)
    cdf = cumsum(weights ./ total_w)
    cdf[end] = 1.0
    return patterns, cdf
end

"""
    generate_synthetic_db(path; n, m, avg_len, n_patterns, avg_pat_len, seed)

Sinh CSDL giao dịch và ghi ra `path` theo đúng định dạng SPMF sạch
(item nguyên dương 1..m tăng dần, không trùng, cách nhau đúng một dấu cách).
"""
function generate_synthetic_db(path::AbstractString;
                               n::Int = SYNTHETIC_N,
                               m::Int = SYNTHETIC_M,
                               avg_len::Real = 10,
                               n_patterns::Int = SYNTHETIC_PATTERNS,
                               avg_pat_len::Float64 = SYNTHETIC_PAT_LEN,
                               seed::Int = SEED)
    rng = MersenneTwister(seed)
    patterns, cdf = generate_patterns(rng, m, n_patterns, avg_pat_len)
    mkpath(dirname(path))

    total_items = 0
    seen_items = falses(m)
    tx = Int[]

    open(path, "w") do io
        for _ in 1:n
            target_len = clamp(rand_poisson(rng, Float64(avg_len)), 1, m)
            empty!(tx)
            while length(tx) < target_len
                pat = patterns[sample_cdf(rng, cdf)]
                if !isempty(tx) && length(tx) + length(pat) > target_len
                    # Chấp nhận vượt mục tiêu 50% số lần để độ dài trung bình sát target_len
                    if rand(rng) < 0.5
                        for x in pat
                            x in tx || push!(tx, x)
                        end
                    end
                    break
                end
                for x in pat
                    x in tx || push!(tx, x)
                end
            end
            # Nếu vẫn ngắn hơn mục tiêu nhiều, bổ sung thêm item ngẫu nhiên
            if isempty(tx)
                push!(tx, rand(rng, 1:m))
            end
            sort!(tx)
            total_items += length(tx)
            @inbounds begin
                for x in tx
                    seen_items[x] = true
                end
                print(io, tx[1])
                for j in 2:length(tx)
                    print(io, ' ', tx[j])
                end
                print(io, '\n')
            end
        end
    end

    actual_m = count(seen_items)
    actual_avg = total_items / n
    return (n = n, m = actual_m, avg_len = actual_avg)
end

function main(args::Vector{String})
    n = SYNTHETIC_N
    m = SYNTHETIC_M
    lens = copy(SYNTHETIC_AVG_LENS)
    out_dir = SYNTHETIC_DIR
    seed = SEED

    i = 1
    while i <= length(args)
        if args[i] == "--n" && i < length(args)
            n = parse(Int, args[i + 1]); i += 2
        elseif args[i] == "--m" && i < length(args)
            m = parse(Int, args[i + 1]); i += 2
        elseif args[i] == "--lens" && i < length(args)
            lens = parse.(Int, split(args[i + 1], ',')); i += 2
        elseif args[i] == "--out-dir" && i < length(args)
            out_dir = args[i + 1]; i += 2
        elseif args[i] == "--seed" && i < length(args)
            seed = parse(Int, args[i + 1]); i += 2
        else
            error("Tham số không hợp lệ: $(args[i])")
        end
    end

    mkpath(out_dir)
    println("Sinh dữ liệu tổng hợp (N=$n, m=$m, seed=$seed) vào $out_dir:")
    for L in lens
        dest = joinpath(out_dir, "synth_L$(L).txt")
        stats = generate_synthetic_db(dest; n = n, m = m, avg_len = L, seed = seed)
        println("  ✓ $(basename(dest)): N=$(stats.n), m=$(stats.m), L̄=$(round(stats.avg_len; digits=2))")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
