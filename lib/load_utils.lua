local load_utils = {}

-- https://stackoverflow.com/questions/33324376/local-variable-cannot-be-seen-in-a-closure-across-the-file?noredirect=1&lq=1


function load_utils.path(n)
   -- https://stackoverflow.com/questions/6380820/get-containing-path-of-lua-file
	local str = debug.getinfo(2 + (n or 0), "S").source:sub(2)
	return (str:match("(.*/)") or "./"):sub(1, -2)
end

function load_utils.relative(r_path, n)
	local a_path = load_utils.path(1 + (n or 0))

	for i, sub in ipairs(r_path:split("/")) do
		a_path = a_path.."/"

		if sub == ".." then
			local path = a_path:split("/")
			local out = ""
			for i = 1, #path-2 do
				out = out..path[i].."/"
			end
			out = out:sub(1, -2)
			a_path = out
		else
			a_path = a_path..sub
		end
	end

	return a_path
end

function load_utils.absolute(r_path, n)
   -- https://stackoverflow.com/questions/44511599/how-to-get-absolute-path-of-a-lua-script-file
   return package.searchpath(load_utils.relative(r_path, 1 + (n or 0)), package.path )
end

function load_utils.load_with_fenv(r_path)
	-- print(load_utils.absolute(r_path, 1))
	return loadfile(load_utils.absolute(r_path, 1), "bt", getfenv(2))()
end

return load_utils
