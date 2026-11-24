# Kiểm thử đọc/ghi định dạng SPMF và quy đổi ngưỡng minsup (mục 7.3).

@testset "parse_minsup" begin
    @test parse_minsup("0.4") == 0.4
    @test parse_minsup("40%") == 0.4
    @test parse_minsup(" 17.5% ") == 17.5 / 100
    @test parse_minsup("1") == 1.0
    @test parse_minsup("100%") == 1.0
    @test parse_minsup("0.01") == 0.01
    @test parse_minsup("1%") == 0.01

    for bad in ("", "   ", "%", "0", "0%", "-0.1", "-5%", "1.01", "101%", "abc", "NaN", "Inf")
        @test_throws ArgumentError parse_minsup(bad)
    end
end

@testset "minsup_count khớp SPMF (Float64)" begin
    # Toàn bộ các ca đã kiểm chứng hộp đen với SPMF ở results/spmf_behavior.md
    cases = [
        (5, "40%", 2),
        (5, "30%", 2),
        (10, "70%", 7),
        (25, "28%", 8),     # 0.28 * 25 = 7.000000000000001 -> ceil = 8 (giống SPMF)
        (50, "14%", 8),     # 0.14 * 50 = 7.000000000000001 -> ceil = 8
        (40, "17.5%", 7),
        (20, "35%", 7),
        (100, "7%", 8),     # 0.07 * 100 = 7.000000000000001 -> ceil = 8
        (10, "0.7", 7),
        (3196, "50%", 1598),
        (0, "40%", 0),
    ]
    for (n, s, expected) in cases
        @test minsup_count(s, n) == expected
        @test minsup_count(parse_minsup(s), n) == expected
    end

    @test_throws ArgumentError minsup_count(0.5, -1)
    @test_throws ArgumentError minsup_count(0.0, 10)
    @test_throws ArgumentError minsup_count(1.5, 10)
end

@testset "read_spmf: metadata, khoảng trắng, trùng lặp, mã rời rạc" begin
    content = """
    @CONVERTED_FROM_TEXT
    @ITEM=1=milk
    # chú thích dấu thăng
    % chú thích dấu phần trăm

       \t
      30   10   30\r
    20\t10\t0
    9999999999 0
    """
    db = read_spmf(IOBuffer(content))
    @test n_transactions(db) == 3
    @test n_items(db) == 5
    @test db.item_ids == Int64[0, 10, 20, 30, 9999999999]
    @test db.transactions == [
        Int32[2, 4],       # 10, 30 (đã sắp xếp và bỏ trùng)
        Int32[1, 2, 3],    # 0, 10, 20
        Int32[1, 5],       # 0, 9999999999
    ]

    # CSDL rỗng (chỉ gồm metadata và dòng rỗng)
    empty_db = read_spmf(IOBuffer("@META\n# comment\n\n   \n"))
    @test n_transactions(empty_db) == 0
    @test n_items(empty_db) == 0

    # Dữ liệu lỗi (không phải số nguyên)
    @test_throws ArgumentError read_spmf(IOBuffer("1 2 abc\n"))
    @test_throws ArgumentError read_spmf(joinpath(REPO_ROOT, "khong_ton_tai_xyz.txt"))
end

@testset "write_itemset và khứ hồi" begin
    db = TransactionDB([Int32[1, 2, 3]], Int64[10, 50, 900])

    # Tập rỗng không ghi gì
    io = IOBuffer()
    write_itemset(io, Int32[], 5, db)
    @test String(take!(io)) == ""

    # Tập 1, 2, 3 phần tử chưa sắp xếp -> ghi theo mã gốc tăng dần, không làm đổi mảng input
    buf = Int32[]
    v1 = Int32[2]
    write_itemset(io, v1, 4, db, buf)
    @test String(take!(io)) == "50 #SUP: 4\n"

    v2 = Int32[3, 1]
    write_itemset(io, v2, 3, db, buf)
    @test String(take!(io)) == "10 900 #SUP: 3\n"
    @test v2 == Int32[3, 1]

    v3 = Int32[3, 1, 2]
    write_itemset(io, v3, 2, db, buf)
    @test String(take!(io)) == "10 50 900 #SUP: 2\n"
    @test v3 == Int32[3, 1, 2]

    # Đọc 2 bộ toy chuẩn
    p99 = read_spmf(joinpath(REPO_ROOT, "data", "toy", "pasquier99.txt"))
    @test n_transactions(p99) == 5
    @test n_items(p99) == 5

    bk = read_spmf(joinpath(REPO_ROOT, "data", "toy", "bookstore.txt"))
    @test n_transactions(bk) == 6
    @test n_items(bk) == 5
end
