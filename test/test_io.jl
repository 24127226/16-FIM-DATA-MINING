# Kiểm thử đọc/ghi định dạng SPMF và quy tắc minsup (phần của B).

parse_str(s::AbstractString) = parse_spmf(Vector{UInt8}(s))

@testset "parse_minsup" begin
    @test parse_minsup("40%") == 40 / 100
    @test parse_minsup("0.4") == 0.4
    @test parse_minsup("17.5%") == 17.5 / 100
    @test parse_minsup(" 1% ") == 1 / 100
    @test parse_minsup("100%") == 1.0
    @test_throws ArgumentError parse_minsup("0%")
    @test_throws ArgumentError parse_minsup("150%")
    @test_throws ArgumentError parse_minsup("1.5")
    @test_throws ArgumentError parse_minsup("-0.1")
end

@testset "minsup_count giống hệt SPMF (results/spmf_behavior.md)" begin
    # (N, minsup, ngưỡng SPMF quan sát được). Các ca 28%/14%/7% lệch khỏi giá trị toán học
    # vì sai số Float64; nhóm phải lệch y hệt SPMF.
    for (n, s, expected) in [(5, "40%", 2), (5, "30%", 2), (10, "70%", 7), (25, "28%", 8),
                             (50, "14%", 8), (40, "17.5%", 7), (20, "35%", 7), (100, "7%", 8),
                             (10, "0.7", 7), (3196, "50%", 1598)]
        @test minsup_count(parse_minsup(s), n) == expected
    end
    @test minsup_count(0.5, 0) == 1          # CSDL rỗng: ngưỡng vẫn ≥ 1
    @test minsup_count(1e-9, 10) == 1
end

@testset "read_spmf: dòng rỗng, chú thích, metadata" begin
    db = parse_str("@FILETYPE=\"x\"\n1 3 4\n\n2 3 5\n# chu thich\n% chu thich\n1 2 3 5\n2 5\n1 2 3 5\n")
    @test n_transactions(db) == 5
    @test db.item_ids == [1, 2, 3, 4, 5]
    @test db.transactions[1] == Int32[1, 3, 4]
    @test db.transactions[4] == Int32[2, 5]
end

@testset "read_spmf: khoảng trắng tùy ý, CRLF, dòng cuối không có xuống dòng" begin
    db = parse_str("  1\t3  4 \r\n2 3 5\r\n1 2 3 5")
    @test n_transactions(db) == 3
    @test db.transactions[1] == Int32[1, 3, 4]
    @test db.transactions[3] == Int32[1, 2, 3, 5]
    @test db.item_ids == [1, 2, 3, 4, 5]
end

@testset "read_spmf: tự sắp xếp và bỏ item trùng" begin
    db = parse_str("3 1 4\n2 3 5 5\n5 2 2\n")
    @test db.transactions[1] == Int32[1, 3, 4]
    @test db.transactions[2] == Int32[2, 3, 5]
    @test db.transactions[3] == Int32[2, 5]
end

@testset "read_spmf: mã rời rạc, mã 0, mã rất lớn" begin
    db = parse_str("7 20 35\n20 35\n7 20 1000000\n0 35\n")
    @test db.item_ids == [0, 7, 20, 35, 1000000]
    @test db.transactions[3] == Int32[2, 3, 5]
    @test db.transactions[4] == Int32[1, 4]
    big = parse_str("100000000000 5\n5\n")          # vượt ngưỡng tra mảng → dùng bảng băm
    @test big.item_ids == [5, 100000000000]
    @test big.transactions[1] == Int32[1, 2]
end

@testset "read_spmf: CSDL rỗng và lỗi định dạng" begin
    @test n_transactions(parse_str("")) == 0
    @test n_transactions(parse_str("@meta\n\n# x\n")) == 0
    @test_throws ArgumentError parse_str("1 2 a\n")
    @test_throws ArgumentError parse_str("1 -2\n")
end

@testset "Ghi kết quả: định dạng SPMF, mã gốc tăng dần" begin
    db = parse_str("7 20 35\n20 35\n")
    io = IOBuffer()
    write_itemset(io, Int32[3, 2], 2, db)              # mã nội bộ chưa sắp xếp
    @test String(take!(io)) == "20 35 #SUP: 2\n"
    w = SPMFWriter(io, db)
    write_itemset!(w, Int32[3, 1], 1)
    write_itemset!(w, Int32[2], 2)
    close_writer!(w)
    @test String(take!(io)) == "7 35 #SUP: 1\n20 #SUP: 2\n"
    @test w.count == 2
end

@testset "load_itemsets, compare_itemsets, fingerprint" begin
    dir = mktempdir()
    a = joinpath(dir, "a.txt"); b = joinpath(dir, "b.txt"); c = joinpath(dir, "c.txt")
    write(a, "@FILETYPE=\"x\"\n1 #SUP: 3\n1 2 #SUP: 2\n2 #SUP: 4\n")
    write(b, "2 #SUP: 4\n2 1 #SUP: 2\n1 #SUP: 3\n")                  # khác thứ tự dòng và thứ tự item
    write(c, "1 #SUP: 3\n1 2 #SUP: 3\n2 #SUP: 4\n")                  # lệch support của {1,2}
    @test load_itemsets(a) == Dict([1] => 3, [1, 2] => 2, [2] => 4)
    @test load_itemsets(a) == load_itemsets(b)
    @test fingerprint(a) == fingerprint(b)
    @test fingerprint(a) != fingerprint(c)
    r = compare_itemsets(load_itemsets(c), load_itemsets(a))
    @test r.matched == 2 && r.diff_support == 1 && r.rate ≈ 2 / 3
    r2 = compare_itemsets(Dict([1] => 1), Dict([2] => 1))
    @test r2.only_ours == 1 && r2.only_ref == 1 && r2.rate == 0.0
    @test compare_itemsets(Dict{Vector{Int},Int}(), Dict{Vector{Int},Int}()).rate == 1.0
end
