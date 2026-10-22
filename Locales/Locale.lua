local _, ns = ...

-- The English text is the key, so a string with no translation shows in English.
ns.L = setmetatable({}, { __index = function(_, key) return key end })
