# Kiểm thử tính đúng của Eclat (phần của B; người viết thuật toán là A).
#
# Ba nguồn đáp án độc lập:
#   1. Đáp án của SPMF cho toy, ví dụ trong bài báo và các ca biên (test/expected/).
#   2. Oracle duyệt trâu: liệt kê cả 2^m tập con rồi đếm trực tiếp (không phụ thuộc SPMF).
#   3. So các phiên bản với nhau: mọi phiên bản phải cho kết quả giống hệt.

const EXPECTED_DIR = joinpath(@__DIR__, "expected")
const REPO_ROOT = normpath(joinpath(@__DIR__, ".."))

"""Các phiên bản đã được cài đặt ở mốc hiện tại (phiên bản chưa cài sẽ bị check_config từ chối)."""
function implemented_variants()
    names = String[]
    for v in VARIANT_NAMES
        try
            EclatFIM.check_config(VARIANTS[v])
            push!(names, v)
        catch
        end
    end
    return names
end

"""Kết quả Eclat đổi sang mã gốc, để so trực tiếp với file SPMF."""
function eclat_original_ids(db, σ, cfg; maxlen = typemax(Int))
    res = Dict{Vector{Int64},Int}()
    eclat!((items, s) -> (res[sort!([db.item_ids[x] for x in items])] = s), db, σ, cfg; maxlen = maxlen)
    return res
end

"""Oracle: duyệt mọi tập con khác rỗng của 1..m (m ≤ 16) và đếm support trực tiếp."""
function brute_force(db::TransactionDB, σ::Integer; maxlen = typemax(Int))
    m = n_items(db)
    masks = [reduce(|, (UInt32(1) << (x - 1) for x in t); init = UInt32(0)) for t in db.transactions]
    res = Dict{Vector{Int32},Int}()
    for S in UInt32(1):(UInt32(1) << m - UInt32(1))
        count_ones(S) > maxlen && continue
        c = count(t -> t & S == S, masks)
        c >= σ && (res[Int32[x for x in 1:m if (S >> (x - 1)) & 1 == 1]] = c)
    end
    return res
end

function random_db(rng, m, n)
    p = rand(rng) * 0.8 + 0.1
    txs = [Int32[x for x in 1:m if rand(rng) < p] for _ in 1:n]
    return TransactionDB(txs, collect(Int64, 1:m))
end

const VARIANTS_HERE = implemented_variants()
@info "Các phiên bản được kiểm thử: $(join(VARIANTS_HERE, ", "))"

@testset "Đáp án SPMF: toy, ví dụ bài báo, ca biên" begin
    cases = [split(l, " | ") for l in eachline(joinpath(EXPECTED_DIR, "manifest.txt")) if !startswith(l, "#")]
    @test length(cases) >= 10
    for (name, input, ms) in cases
        db = read_spmf(joinpath(REPO_ROOT, input))
        σ = minsup_count(parse_minsup(ms), n_transactions(db))
        ref = load_itemsets(joinpath(EXPECTED_DIR, name * ".txt"))
        for v in VARIANTS_HERE
            @test eclat_original_ids(db, σ, VARIANTS[v]) == ref
        end
    end
end

@testset "Đúng số tập như tài liệu SPMF và bài báo" begin
    for v in VARIANTS_HERE
        p = read_spmf(joinpath(REPO_ROOT, "data", "toy", "pasquier99.txt"))
        @test length(eclat(p, 2, VARIANTS[v])) == 15          # tài liệu SPMF
        b = read_spmf(joinpath(REPO_ROOT, "data", "toy", "bookstore.txt"))
        rb = eclat(b, 3, VARIANTS[v])
        @test length(rb) == 19                                  # bài báo, Fig. 1
        @test rb[Int32[1, 2, 4, 5]] == 3                        # tập tối đại ACTW
        @test rb[Int32[2, 3, 5]] == 3                           # tập tối đại CDW
    end
end

@testset "Oracle duyệt trâu: 200 CSDL ngẫu nhiên × mọi phiên bản" begin
    for seed in 1:200
        rng = MersenneTwister(seed)
        m = rand(rng, 1:12)
        n = rand(rng, 0:30)
        db = random_db(rng, m, n)
        σ = rand(rng, 1:max(n, 1))
        ref = brute_force(db, σ)
        for v in VARIANTS_HERE
            res = eclat(db, σ, VARIANTS[v])
            res == ref || @error "Sai ở seed=$seed, phiên bản $v (m=$m, N=$n, σ=$σ)"
            @test res == ref
        end
    end
end

@testset "Mọi tổ hợp cấu hình hợp lệ, kể cả nhánh chuyển bitset → vector của bản lai" begin
    configs = unique(vec([EclatConfig(tidset = t, order = o, reuse = true, isect = i, level2 = l, hybrid_ratio = h)
                          for t in (:vector, :bitset, :hybrid), o in (:lexical, :support_asc),
                              i in (:merge, :adaptive), l in (:intersect, :triangular), h in (1 / 32, 0.3, 0.7)]))
    switched = 0
    for seed in 1:40
        rng = MersenneTwister(1000 + seed)
        m = rand(rng, 2:12)
        n = rand(rng, 1:40)
        db = random_db(rng, m, n)
        σ = rand(rng, 1:n)
        ref = brute_force(db, σ)
        for cfg in configs
            st = EclatStats()
            res = Dict{Vector{Int32},Int}()
            eclat!((items, s) -> (res[sort(items)] = s), db, σ, cfg; stats = st)
            res == ref || @error "Sai ở seed=$seed với $cfg"
            @test res == ref
            switched += st.n_switch
        end
    end
    @test switched > 0          # nhánh chuyển biểu diễn thật sự được chạy trong bộ test
end

@testset "Bản lai ở ngưỡng mặc định trên CSDL lớn hơn (so với v0)" begin
    rng = MersenneTwister(77)
    for p in (0.02, 0.1, 0.3)
        db = TransactionDB([Int32[x for x in 1:25 if rand(rng) < p] for _ in 1:3000], collect(Int64, 1:25))
        σ = p < 0.05 ? 3 : (p < 0.2 ? 20 : 150)
        ref = eclat(db, σ, VARIANTS["v0"])
        st = EclatStats()
        res = Dict{Vector{Int32},Int}()
        eclat!((items, s) -> (res[sort(items)] = s), db, σ, VARIANTS["v6"]; stats = st)
        @test res == ref
        @test length(ref) > 25
    end
end

@testset "maxlen: giới hạn kích thước tập" begin
    rng = MersenneTwister(2026)
    for _ in 1:30
        db = random_db(rng, 10, 25)
        for L in 1:4, v in VARIANTS_HERE
            @test eclat(db, 3, VARIANTS[v]; maxlen = L) == brute_force(db, 3; maxlen = L)
        end
    end
end

@testset "Hợp đồng của sink: mỗi tập đúng một lần, thứ tự xác định" begin
    db = read_spmf(joinpath(REPO_ROOT, "data", "toy", "bookstore.txt"))
    for v in VARIANTS_HERE
        seen = Vector{Int32}[]
        eclat!((items, s) -> push!(seen, sort(items)), db, 2, VARIANTS[v])
        @test length(seen) == length(unique(seen))
        again = Vector{Int32}[]
        eclat!((items, s) -> push!(again, sort(items)), db, 2, VARIANTS[v])
        @test seen == again
        @test all(!isempty, seen)
    end
end

@testset "Mã item rất lớn và rời rạc (SPMF Eclat không chạy được ca này)" begin
    db = parse_spmf(Vector{UInt8}("7 20 35\n20 35\n7 20 1000000\n35 1000000\n20 35 1000000\n"))
    expected = Dict([35] => 4, [20] => 4, [7] => 2, [1000000] => 3, [7, 20] => 2,
                    [35, 1000000] => 2, [20, 1000000] => 2, [20, 35] => 3)
    for v in VARIANTS_HERE
        @test eclat_original_ids(db, 2, VARIANTS[v]) == expected
    end
end

@testset "CSDL rỗng, không có item phổ biến" begin
    empty_db = TransactionDB(Vector{Int32}[], Int64[])
    for v in VARIANTS_HERE
        @test isempty(eclat(empty_db, 1, VARIANTS[v]))
        @test isempty(eclat(read_spmf(joinpath(REPO_ROOT, "test", "data", "edge_none.txt")), 2, VARIANTS[v]))
    end
    @test_throws ArgumentError eclat(empty_db, 0, VARIANTS["v0"])
end
