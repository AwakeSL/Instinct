--!strict

return function(i: any)
	i:operator("times", {
		stage = 2,
		costs = 0.004,
		apply = function(a: number, b: number): number?
			return a * b
		end,
	})

	i:operator("over", {
		stage = 2,
		costs = 0.006,
		apply = function(a: number, b: number): number?
			if b == 0 then
				return nil
			end
			return a / b
		end,
	})

	i:operator("inverted", {
		stage = 2,
		costs = 0.004,
		apply = function(a: number, b: number): number?
			if b == 0 then
				return nil
			end
			return math.clamp(1 - a / b, 0, 1)
		end,
	})

	i:operator("atLeast", {
		stage = 3,
		costs = 0.002,
		apply = function(a: number, b: number): number?
			return math.max(a, b)
		end,
	})

	i:operator("atMost", {
		stage = 3,
		costs = 0.002,
		apply = function(a: number, b: number): number?
			return math.min(a, b)
		end,
	})

	i:operator("threshold", {
		stage = 3,
		costs = 0.010,
		apply = function(a: number, b: number): number?
			return if a >= b then 1 else 0
		end,
	})

	return i
end
