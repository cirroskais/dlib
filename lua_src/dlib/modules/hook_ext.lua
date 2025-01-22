hook.__table = hook.__table or {}
hook.__tableTasks = hook.__tableTasks or {}
hook.__tableModifiersPost = hook.__tableModifiersPost or {}
hook.__disabled = hook.__disabled or {}

local __table = hook.__table
local __tableTasks = hook.__tableTasks
local __tableModifiersPost = hook.__tableModifiersPost
local __disabled = hook.__disabled

local function transformStringID(funcname, stringID, event)
	if isstring(stringID) then return stringID end
	if type(stringID) == 'thread' then return stringID end

	if type(stringID) == 'number' then
		stringID = tostring(stringID)
	end

	if type(stringID) == 'boolean' then
		error(string.format('bad argument #2 to %s (object expected, got boolean)', funcname), 3)
	end

	if type(stringID) ~= 'string' then
		local success = pcall(function()
			stringID.IsValid(stringID)
		end)

		if not success then
			error(string.format('bad argument #2 to %s (object expected, got %s)', funcname, type(stringID)), 3)
			stringID = tostring(stringID)
		end
	end

	return stringID
end


function hook.DisableHook(event, stringID)
	assert(type(event) == 'string', 'hook.DisableHook - event is not a string! ' .. type(event))

	if not stringID then
		if __disabled[event] then
			return false
		end

		__disabled[event] = true
		hook.Reconstruct(event)
		return true
	end

	if not __table[event] then return end

	stringID = transformStringID('hook.DisableHook', stringID, event)

	for priority, eventData in pairs(__table[event]) do
		if eventData[stringID] then
			local wasDisabled = eventData[stringID].disabled
			eventData[stringID].disabled = true
			hook.Reconstruct(event)
			return not wasDisabled
		end
	end
end

function hook.Reconstruct(eventToReconstruct)
	if not eventToReconstruct then
		for event, data in pairs(__table) do
			hook.Reconstruct(event)
		end

		return
	end

	if __disabled[eventToReconstruct] then
		__tableOptimized[eventToReconstruct] = identity
		return
	elseif not __table[eventToReconstruct] then
		__tableOptimized[eventToReconstruct] = gamemodePassthrough
		return
	end

	local index = 1
	local inboundgmod = __tableGmod[eventToReconstruct]

	local callables = {}

	for priority, hookList in SortedPairs(__table[eventToReconstruct]) do
		for stringID, hookData in pairs(hookList) do
			if not hookData.disabled then
				local isValid = false

				if hookData.typeof then
					isValid = true
				elseif hookData.isthread then
					if coroutine.status(hookData.id) == 'dead' then
						hookList[stringID] = nil
						inboundgmod[stringID] = nil
					else
						isValid = true
					end
				else
					if hookData.id:IsValid() then
						isValid = true
					else
						hookList[stringID] = nil
						inboundgmod[stringID] = nil
					end
				end

				if isValid then
					local callable

					if hookData.typeof then
						callable = hookData.callback or hookData.funcToCall
					elseif hookData.isthread then
						local self = hookData.id
						local upvalue = hookData.callback

						function callable(...)
							if coroutine.status(self) == 'dead' then
								hook.Remove(hookData.event, self)
								return
							end

							return upvalue(self, ...)
						end
					else
						local self = hookData.id
						local upvalue = hookData.callback or hookData.funcToCall

						function callable(...)
							if not self:IsValid() then
								hook.Remove(hookData.event, self)
								return
							end

							return upvalue(self, ...)
						end
					end

					if hook.PROFILING then
						local THIS_RUNTIME = 0
						local THIS_CALLS = 0
						local upfuncProfiled = callable

						function callable(...)
							THIS_CALLS = THIS_CALLS + 1
							local t = SysTime()
							local a, b, c, d, e, f = upfuncProfiled(...)
							THIS_RUNTIME = THIS_RUNTIME + (SysTime() - t)
							return a, b, c, d, e, f
						end

						function hookData.profileEnds()
							hookData.THIS_RUNTIME = THIS_RUNTIME
							hookData.THIS_CALLS = THIS_CALLS
						end
					end

					callables[index] = callable
					index = index + 1
				end
			end
		end
	end

	local post = {}
	local postIndex = 1

	if __tableModifiersPost[eventToReconstruct] ~= nil then
		local event = __tableModifiersPost[eventToReconstruct]

		for stringID, hookData in pairs(event) do
			local isValid = false

			if hookData.typeof then
				isValid = true
			else
				if hookData.id:IsValid() then
					isValid = true
				else
					event[stringID] = nil
				end
			end

			if isValid then
				post[postIndex] = hookData.callback or hookData.funcToCall
				postIndex = postIndex + 1
			end
		end
	end

	if index == 1 and postIndex == 1 then
		__tableOptimized[eventToReconstruct] = gamemodePassthrough
	elseif index ~= 1 and postIndex == 1 then
		__tableOptimized[eventToReconstruct] = function(event, tab, ...)
			local a, b, c, d, e, f

			for i = 1, index - 1 do
				a, b, c, d, e, f = callables[i](...)
				if a ~= nil then return a, b, c, d, e, f end
			end

			return gamemodePassthrough(event, tab, ...)
		end
	elseif index == 1 and postIndex ~= 1 then
		__tableOptimized[eventToReconstruct] = function(event, tab, ...)
			if tab ~= nil then
				local a, b, c, d, e, f = gamemodePassthrough(event, tab, ...)

				if a ~= nil then
					for i2 = 1, postIndex - 1 do
						a, b, c, d, e, f = post[i2](a, b, c, d, e, f)
					end

					return a, b, c, d, e, f
				end
			end
		end
	else
		__tableOptimized[eventToReconstruct] = function(event, tab, ...)
			local a, b, c, d, e, f

			for i = 1, index - 1 do
				a, b, c, d, e, f = callables[i](...)

				if a ~= nil then
					for i2 = 1, postIndex - 1 do
						a, b, c, d, e, f = post[i2](a, b, c, d, e, f)
					end

					return a, b, c, d, e, f
				end
			end

			if tab ~= nil then
				a, b, c, d, e, f = gamemodePassthrough(event, tab, ...)

				if a ~= nil then
					for i2 = 1, postIndex - 1 do
						a, b, c, d, e, f = post[i2](a, b, c, d, e, f)
					end

					return a, b, c, d, e, f
				end
			end
		end
	end
end

function hook.AddTask(event, stringID, callback)
	assert(type(event) == 'string', 'bad argument #1 to hook.AddTask (string expected, got ' .. type(event) .. ')', 2)
	assert(type(callback) == 'function', 'bad argument #3 to hook.AddTask (function expected, got ' .. type(callback) .. ')', 2)

	stringID = transformStringID('hook.AddTask', stringID, event)

	local hookData = {
		event = event,
		callback = callback,
		id = stringID,
		idString = tostring(stringID),
		registeredAt = SysTime(),
		typeof = isstring(stringID)
	}

	__tableTasks[event] = __tableTasks[event] or {}
	__tableTasks[event][stringID] = hookData

	hook.ReconstructTasks(event)
end

function hook.AddPostModifier(event, stringID, callback)
	__tableModifiersPost[event] = __tableModifiersPost[event] or {}

	if type(event) ~= 'string' then
		DLib.Message(traceback('hook.AddPostModifier - event is not a string! ' .. type(event)))
		return false
	end

	if type(callback) ~= 'function' then
		DLib.Message(traceback('hook.AddPostModifier - function is not a function! ' .. type(funcToCall)))
		return false
	end

	stringID = transformStringID('hook.AddPostModifier', stringID, event)

	local hookData = {
		event = event,
		callback = callback,
		id = stringID,
		idString = tostring(stringID),
		registeredAt = SysTime(),
		typeof = isstring(stringID)
	}

	__tableModifiersPost[event][stringID] = hookData
	hook.Reconstruct(event)
	return true, hookData
end

function hook.ReconstructTasks(eventToReconstruct)
	if not eventToReconstruct then
		for event, data in pairs(__tableTasks) do
			hook.ReconstructTasks(event)
		end

		return
	end

	if not __tableTasks[eventToReconstruct] or not next(__tableTasks[eventToReconstruct]) then
		hook.Remove(eventToReconstruct, 'DLib Task Executor')
		return
	end

	local index = 1
	local target = {}
	local target_funcs = {}
	local target_data = {}
	local ignore_dead = false

	for stringID, hookData in pairs(__tableTasks[eventToReconstruct]) do
		if not hookData.disabled then
			local applicable = false

			if hookData.typeof then
				applicable = true
			else
				if hookData.id:IsValid() then
					applicable = true
				else
					hookList[stringID] = nil
					inboundgmod[stringID] = nil
				end
			end

			if applicable then
				local callable

				if hookData.typeof then
					callable = hookData.callback
				else
					local self = hookData.id
					local upfuncCallableSelf = hookData.callback

					function callable()
						if not self:IsValid() then
							ignore_dead = true
							hook.RemoveTask(hookData.event, self)
							return
						end

						return upfuncCallableSelf(self)
					end
				end

				if not hookData.thread or coroutine.status(hookData.thread) == 'dead' then
					hookData.thread = coroutine.create(callable)
				end

				target[index] = hookData.thread
				target_funcs[index] = callable
				target_data[index] = hookData
				index = index + 1
			end
		end
	end

	index = index - 1

	if index == 0 then
		hook.Remove(eventToReconstruct, 'DLib Task Executor')
		return
	end

	local task_i = 0

	hook.Add(eventToReconstruct, 'DLib Task Executor', function()
		task_i = task_i + 1

		if task_i > index then
			task_i = 1
		end

		local thread = target[task_i]
		ignore_dead = false
		local status, err = coroutine.resume(thread)

		if not status then
			target[task_i] = coroutine.create(target_funcs[task_i])
			target_data[task_i].thread = target[task_i]
			error('Task ' .. target_data[task_i].idString .. ' failed: ' .. err)
		end

		if not ignore_dead and coroutine.status(thread) == 'dead' then
			target[task_i] = coroutine.create(target_funcs[task_i])
			target_data[task_i].thread = target[task_i]
		end
	end)
end