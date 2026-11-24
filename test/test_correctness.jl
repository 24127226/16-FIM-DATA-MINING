# Kiểm chứng tính đúng của Eclat (tầng 1: oracle duyệt trâu 200 CSDL ngẫu nhiên;
# tầng 2: ví dụ chuẩn Pasquier99, Bookstore và các ca biên; so sánh output/fingerprint).

include(joinpath(REPO_ROOT, "scripts", "compare_spmf.jl"))

"""
    brute_force_oracle(db, minsup) -> Dict{Vector{Int32}, Int}

Oracle duyệt trâu độc lập hoàn toàn với Eclat và SPMF: liệt kê toàn bộ 2^m - 1 tập con
khác rỗng và đếm trực tiếp số giao dịch chứa từng tập. Chỉ dùng cho m ≤ 14.
"""
function brute_force_oracle(db::TransactionDB, minsup::Integer)::Dict{Vector{Int32},Int}
    m = n_items(db)
    @assert m <= 14 "Oracle duyệt trâu chỉ dùng cho m ≤ 14"
    res = Dict{Vector{Int32},Int}()
    (m == 0 || n_transactions(db) == 0) && return res

    # Biểu diễn mỗi giao dịch thành bitmask UInt32 để kiểm tra tập con bằng phép AND bit
    tx_masks = Vector{UInt32}(undef, n_transactions(db))
    for (idx, t) in enumerate(db.transactions)
        mask = UInt32(0)
        for x in t
            mask |= UInt32(1) << (x - 1)
        end
        tx_masks[idx] = mask
    end

    limit = (UInt32(1) << m) - UInt32(1)
    for subset_mask in UInt32(1):limit
        sup = 0
        @inbounds for tm in tx_masks
            if (tm & subset_mask) == subset_mask
                sup += 1
            end
        end
        if sup >= minsup
            items = Int32[Int32(bit) for bit in 1:m if (subset_mask & (UInt32(1) << (bit - 1))) != 0]
            res[items] = sup
        end
    end
    return res
end

"""Sinh CSDL ngẫu nhiên với seed cố định (m ≤ 12, N ≤ 30)."""
function random_db(seed::Int)
    rng = MersenneTwister(seed)
    m = rand(rng, 1:12)
    n = rand(rng, 1:30)
    p = rand(rng) * 0.7 + 0.15    # xác suất mỗi item xuất hiện trong giao dịch ∈ [0.15, 0.85]
    txs = Vector{Vector{Int32}}(undef, n)
    for i in 1:n
        txs[i] = Int32[Int32(x) for x in 1:m if rand(rng) < p]
    end
    item_ids = Int64.(1:m)
    minsup = rand(rng, 1:max(1, n ÷ 2))
    return TransactionDB(txs, item_ids), minsup
end

const VARIANTS_TO_TEST = available_variants()

@testset "Phiên bản khả dụng" begin
    @test !isempty(VARIANTS_TO_TEST)
    @test any(v -> v[1] == "v0", VARIANTS_TO_TEST)
end

@testset "Ví dụ chuẩn: Pasquier99 (15 tập) và Bookstore (19 tập)" begin
    p99 = read_spmf(joinpath(REPO_ROOT, "data", "toy", "pasquier99.txt"))
    p99_minsup = minsup_count("40%", n_transactions(p99))
    @test p99_minsup == 2
    p99_oracle = brute_force_oracle(p99, p99_minsup)
    @test length(p99_oracle) == 15

    bk = read_spmf(joinpath(REPO_ROOT, "data", "toy", "bookstore.txt"))
    bk_minsup = minsup_count("50%", n_transactions(bk))
    @test bk_minsup == 3
    bk_oracle = brute_force_oracle(bk, bk_minsup)
    @test length(bk_oracle) == 19
    # Hai tập tối đại theo bài báo Zaki (2000) Fig. 1: ACTW (1 2 4 5) và CDW (2 3 5)
    @test bk_oracle[Int32[1, 2, 4, 5]] == 3
    @test bk_oracle[Int32[2, 3, 5]] == 3

    for (vname, cfg) in VARIANTS_TO_TEST
        @testset "variant $vname" begin
            @test eclat(p99, p99_minsup, cfg) == p99_oracle
            @test eclat(bk, bk_minsup, cfg) == bk_oracle

            # Kiểm tra EclatStats nhất quán
            st = EclatStats()
            cnt = Ref(0)
            eclat!((items, s) -> (cnt[] += 1), bk, bk_minsup, cfg; stats = st)
            @test cnt[] == 19
            @test st.n_itemsets == 19
            @test st.max_depth == 4
            @test st.bytes_current == 0
            @test st.bytes_peak > 0

            # Kiểm tra giới hạn độ dài maxlen = 2
            res_max2 = eclat(bk, bk_minsup, cfg; maxlen = 2)
            @test all(length(k) <= 2 for k in keys(res_max2))
            @test res_max2 == Dict(k => v for (k, v) in bk_oracle if length(k) <= 2)
        end
    end
end

@testset "Tầng 1: Oracle duyệt trâu trên 200 CSDL ngẫu nhiên (seed 1..200)" begin
    for (vname, cfg) in VARIANTS_TO_TEST
        @testset "variant $vname" begin
            all_match = true
            for seed in 1:200
                db, ms = random_db(seed)
                expected = brute_force_oracle(db, ms)
                got = eclat(db, ms, cfg)
                if got != expected
                    all_match = false
                    @test got == expected
                    break
                end
            end
            @test all_match
        end
    end
end

@testset "Các ca biên (edge cases)" begin
    edge_cases = [
        ("CSDL rỗng", read_spmf(IOBuffer("")), 1),
        ("1 giao dịch", read_spmf(IOBuffer("10 20 30\n")), 1),
        ("Giao dịch giống hệt nhau", read_spmf(IOBuffer("1 2 3\n1 2 3\n1 2 3\n")), 3),
        ("minsup = 100%", read_spmf(IOBuffer("1 2 3\n1 2\n1 2 4\n")), 3),
        ("Không tập nào đạt ngưỡng", read_spmf(IOBuffer("1 2\n3 4\n5 6\n")), 2),
        ("Mã item lớn rời rạc & trùng lặp", read_spmf(IOBuffer("500000 10 10\n10 999999999 500000\n")), 2),
    ]
    for (label, db, ms) in edge_cases
        expected = brute_force_oracle(db, ms)
        for (vname, cfg) in VARIANTS_TO_TEST
            @testset "$label ($vname)" begin
                @test eclat(db, ms, cfg) == expected
            end
        end
    end
end

@testset "compare_spmf.jl (Dict & Fingerprint)" begin
    p99 = read_spmf(joinpath(REPO_ROOT, "data", "toy", "pasquier99.txt"))
    res = eclat(p99, 2, VARIANTS["v0"])

    dir = mktempdir()
    f1 = joinpath(dir, "out1.txt")
    f2 = joinpath(dir, "out2.txt")

    # Ghi f1 theo thứ tự bình thường, f2 theo thứ tự đảo ngược dòng & đảo ngược item
    open(f1, "w") do io
        for (items, sup) in res
            write_itemset(io, items, sup, p99)
        end
    end
    lines = readlines(f1)
    open(f2, "w") do io
        for line in reverse(lines)
            items, sup = parse_spmf_output_line(line)
            println(io, join(reverse(items), ' '), " #SUP: ", sup)
        end
    end

    r_exact = compare_files(f1, f2)
    @test r_exact.exact_match
    @test r_exact.match_pct == 100.0
    @test r_exact.n_match == 15

    r_fp = compare_files(f1, f2; force_fingerprint = true)
    @test r_fp.exact_match
    @test r_fp.n_ours == 15
    @test r_fp.hash_ours == r_fp.hash_ref

    # Thử sửa 1 dòng support để chắc chắn phát hiện sai lệch
    f3 = joinpath(dir, "out3.txt")
    open(f3, "w") do io
        for (idx, line) in enumerate(lines)
            println(io, idx == 1 ? replace(line, r"#SUP: \d+" => "#SUP: 999") : line)
        end
    end
    r_diff = compare_files(f1, f3)
    @test !r_diff.exact_match
    @test r_diff.diff_support == 1
    @test !compare_files(f1, f3; force_fingerprint = true).exact_match
end
