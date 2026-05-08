local last_cmd

local function reset_vim(output, code)
	last_cmd = nil
	_G.vim = {
		split = function(value, sep, opts)
			local result = {}
			local start = 1
			while true do
				local stop = value:find(sep, start, opts and opts.plain)
				if not stop then
					local item = value:sub(start)
					if item ~= "" or not (opts and opts.trimempty) then
						table.insert(result, item)
					end
					break
				end
				local item = value:sub(start, stop - 1)
				if item ~= "" or not (opts and opts.trimempty) then
					table.insert(result, item)
				end
				start = stop + #sep
			end
			return result
		end,
		system = function(cmd)
			last_cmd = cmd
			return {
				wait = function()
					return {
						code = code or 0,
						stdout = output or "",
					}
				end,
			}
		end,
	}

	package.loaded["etoile.git_status"] = nil
	package.loaded["etoile.path"] = nil
end

describe("etoile.git_status", function()
	it("collects file statuses and aggregates descendant statuses onto directories by priority", function()
		reset_vim(" M src/a.lua\0 D src/b.lua\0?? README.md\0!! ignored.log\0")
		local git_status = require("etoile.git_status")

		local statuses = git_status.collect("/tmp/project", { show_ignored = true })

		assert.are.same("modified", git_status.status_for(statuses, "/tmp/project/src/a.lua"))
		assert.are.same("deleted", git_status.status_for(statuses, "/tmp/project/src/b.lua"))
		assert.are.same("deleted", git_status.status_for(statuses, "/tmp/project/src"))
		assert.are.same("added", git_status.status_for(statuses, "/tmp/project/README.md"))
		assert.are.same("ignored", git_status.status_for(statuses, "/tmp/project/ignored.log"))
		assert.are.same("--ignored=matching", last_cmd[#last_cmd])
	end)

	it("does not mark staged added files", function()
		reset_vim("A  staged.lua\0")
		local git_status = require("etoile.git_status")

		local statuses = git_status.collect("/tmp/project")

		assert.are.same(nil, git_status.status_for(statuses, "/tmp/project/staged.lua"))
	end)

	it("does not aggregate ignored files onto ancestor directories", function()
		reset_vim("!! src/generated.log\0")
		local git_status = require("etoile.git_status")

		local statuses = git_status.collect("/tmp/project", { show_ignored = true })

		assert.are.same("ignored", git_status.status_for(statuses, "/tmp/project/src/generated.log"))
		assert.are.same(nil, git_status.status_for(statuses, "/tmp/project/src"))
		assert.are.same(nil, git_status.status_for(statuses, "/tmp/project"))
	end)

	it("marks both rename paths as renamed", function()
		reset_vim("R  new.lua\0old.lua\0")
		local git_status = require("etoile.git_status")

		local statuses = git_status.collect("/tmp/project")

		assert.are.same("renamed", git_status.status_for(statuses, "/tmp/project/new.lua"))
		assert.are.same("renamed", git_status.status_for(statuses, "/tmp/project/old.lua"))
	end)

	it("treats descendants of ignored directories as ignored", function()
		reset_vim("!! dist/\0")
		local git_status = require("etoile.git_status")

		local statuses = git_status.collect("/tmp/project", { show_ignored = true })

		assert.are.same("ignored", git_status.status_for(statuses, "/tmp/project/dist"))
		assert.are.same("ignored", git_status.status_for(statuses, "/tmp/project/dist/bundle.js"))
	end)

	it("returns empty statuses when git status fails", function()
		reset_vim("", 128)
		local git_status = require("etoile.git_status")

		local statuses = git_status.collect("/tmp/project")

		assert.are.same(nil, git_status.status_for(statuses, "/tmp/project/main.lua"))
	end)
end)
