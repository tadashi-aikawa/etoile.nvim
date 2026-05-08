local layout = require("etoile.layout")

describe("etoile.layout", function()
	describe("resolve_height", function()
		it("uses the larger max height between absolute and ratio", function()
			local height = layout.resolve_height({
				height_ratio = 0.8,
				max_height = 50,
				max_height_ratio = 0.8,
				min_height = 10,
				min_height_ratio = 0.2,
			}, 80, 76)

			assert.are.equal(64, height)
		end)

		it("uses the smaller min height between absolute and ratio", function()
			local height = layout.resolve_height({
				height_ratio = 0.1,
				max_height = 50,
				max_height_ratio = 0.8,
				min_height = 10,
				min_height_ratio = 0.05,
			}, 80, 76)

			assert.are.equal(8, height)
		end)

		it("keeps the height within the viewport", function()
			local height = layout.resolve_height({
				height_ratio = 1,
				max_height = 200,
				max_height_ratio = 1,
				min_height = 10,
				min_height_ratio = 0.2,
			}, 80, 76)

			assert.are.equal(76, height)
		end)
	end)

	describe("resolve_row", function()
		it("centers the float vertically", function()
			local row = layout.resolve_row(40, 100)

			assert.are.equal(30, row)
		end)

		it("keeps the float visible when it is taller than the editor", function()
			local row = layout.resolve_row(120, 100)

			assert.are.equal(0, row)
		end)
	end)

	describe("resolve_col", function()
		it("uses the anchor column when the float fits", function()
			local col = layout.resolve_col(44, 80, 160, 2)

			assert.are.equal(44, col)
		end)

		it("shifts left when the float would overflow the editor", function()
			local col = layout.resolve_col(144, 80, 160, 2)

			assert.are.equal(78, col)
		end)

		it("reserves right-side space for another float", function()
			local col = layout.resolve_col(96, 40, 180, 122)

			assert.are.equal(18, col)
		end)

		it("keeps the float visible when it is wider than the available space", function()
			local col = layout.resolve_col(10, 80, 60, 2)

			assert.are.equal(0, col)
		end)
	end)
end)
